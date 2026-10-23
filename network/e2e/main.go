// A userspace harness: two real wireguard-go devices, each backed by a fake TUN,
// configured from exactly the UAPI files the Swift product code generated.
//
// No root and no utun: the WireGuard implementation, its crypto and its UDP
// transport are the real ones; only the kernel interface is replaced, so this
// measures the configuration rather than the harness.
package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

type fakeTUN struct {
	name  string
	in    chan []byte
	out   chan []byte
	mtu   int
	close chan struct{}
	once  sync.Once
}

func newFakeTUN(name string, mtu int) *fakeTUN {
	return &fakeTUN{
		name:  name,
		in:    make(chan []byte, 64),
		out:   make(chan []byte, 64),
		mtu:   mtu,
		close: make(chan struct{}),
	}
}

func (t *fakeTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	select {
	case pkt := <-t.out:
		sizes[0] = copy(bufs[0][offset:], pkt)
		return 1, nil
	case <-t.close:
		return 0, os.ErrClosed
	}
}

func (t *fakeTUN) Write(bufs [][]byte, offset int) (int, error) {
	for _, b := range bufs {
		pkt := make([]byte, len(b)-offset)
		copy(pkt, b[offset:])
		select {
		case t.in <- pkt:
		case <-t.close:
			return 0, os.ErrClosed
		}
	}
	return len(bufs), nil
}

func (t *fakeTUN) MTU() (int, error)                 { return t.mtu, nil }
func (t *fakeTUN) Name() (string, error)             { return t.name, nil }
func (t *fakeTUN) Events() <-chan tun.Event          { return nil }
func (t *fakeTUN) Close() error                      { t.once.Do(func() { close(t.close) }); return nil }
func (t *fakeTUN) File() *os.File                    { return nil }

func checksum(data []byte) uint16 {
	var sum uint32
	for i := 0; i+1 < len(data); i += 2 {
		sum += uint32(binary.BigEndian.Uint16(data[i:]))
	}
	if len(data)%2 == 1 {
		sum += uint32(data[len(data)-1]) << 8
	}
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	return ^uint16(sum)
}

// IPv4 ICMP echo request from src to dst, payload carries `tag`.
func icmpEcho(src, dst net.IP, id uint16, tag string) []byte {
	payload := []byte(tag)
	icmp := make([]byte, 8+len(payload))
	icmp[0] = 8 // echo request
	icmp[4], icmp[5] = byte(id>>8), byte(id)
	icmp[6], icmp[7] = 0, 1
	copy(icmp[8:], payload)
	binary.BigEndian.PutUint16(icmp[2:], checksum(icmp))

	pkt := make([]byte, 20+len(icmp))
	pkt[0] = 0x45
	binary.BigEndian.PutUint16(pkt[2:], uint16(len(pkt)))
	pkt[8] = 64 // ttl
	pkt[9] = 1  // icmp
	copy(pkt[12:], src.To4())
	copy(pkt[16:], dst.To4())
	binary.BigEndian.PutUint16(pkt[10:], checksum(pkt[:20]))
	copy(pkt[20:], icmp)
	return pkt
}

func describe(pkt []byte) string {
	if len(pkt) < 28 {
		return fmt.Sprintf("%d bytes", len(pkt))
	}
	src := net.IP(pkt[12:16])
	dst := net.IP(pkt[16:20])
	if pkt[9] == 1 {
		kind := "?"
		switch pkt[20] {
		case 8:
			kind = "echo-request"
		case 0:
			kind = "echo-reply"
		}
		return fmt.Sprintf("%s -> %s icmp %s payload=%q", src, dst, kind, string(pkt[28:]))
	}
	return fmt.Sprintf("%s -> %s proto %d", src, dst, pkt[9])
}

func handshakeText(dev *device.Device) string {
	state, err := dev.IpcGet()
	if err != nil {
		return "IpcGet failed: " + err.Error()
	}
	scanner := bufio.NewScanner(strings.NewReader(state))
	var out []string
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "last_handshake_time_sec=") ||
			strings.HasPrefix(line, "last_handshake_time_nsec=") ||
			strings.HasPrefix(line, "rx_bytes=") ||
			strings.HasPrefix(line, "tx_bytes=") {
			out = append(out, line)
		}
	}
	if len(out) == 0 {
		return "no handshake fields"
	}
	return strings.Join(out, " ")
}

func handshakeSeconds(dev *device.Device) int64 {
	state, _ := dev.IpcGet()
	for _, line := range strings.Split(state, "\n") {
		if strings.HasPrefix(line, "last_handshake_time_sec=") {
			v, _ := strconv.ParseInt(strings.TrimPrefix(line, "last_handshake_time_sec="), 10, 64)
			return v
		}
	}
	return 0
}

// allowedIPOf returns the /32 the *other* side advertised, which is this side's
// address in the end-to-end topology.
func allowedIPOf(other []byte) net.IP {
	for _, line := range strings.Split(string(other), "\n") {
		if strings.HasPrefix(line, "allowed_ip=") {
			ip := strings.SplitN(strings.TrimPrefix(line, "allowed_ip="), "/", 2)[0]
			return net.ParseIP(ip).To4()
		}
	}
	return nil
}

// The two configuration files are passed as arguments, so this harness has no
// dependency on a fixed scratch path.
func pathA() string {
	if len(os.Args) > 1 {
		return os.Args[1]
	}
	return "a.uapi"
}

func pathB() string {
	if len(os.Args) > 2 {
		return os.Args[2]
	}
	return "b.uapi"
}

func main() {
	uapiA, err := os.ReadFile(pathA())
	if err != nil {
		fmt.Println("FAIL read a.uapi:", err)
		os.Exit(1)
	}
	uapiB, err := os.ReadFile(pathB())
	if err != nil {
		fmt.Println("FAIL read b.uapi:", err)
		os.Exit(1)
	}

	logger := device.NewLogger(device.LogLevelError, "")
	tunA := newFakeTUN("tunA", 1420)
	tunB := newFakeTUN("tunB", 1420)
	devA := device.NewDevice(tunA, conn.NewDefaultBind(), logger)
	devB := device.NewDevice(tunB, conn.NewDefaultBind(), logger)
	defer devA.Close()
	defer devB.Close()

	if err := devA.IpcSet(string(uapiA)); err != nil {
		fmt.Println("FAIL IpcSet A:", err)
		os.Exit(1)
	}
	if err := devB.IpcSet(string(uapiB)); err != nil {
		fmt.Println("FAIL IpcSet B:", err)
		os.Exit(1)
	}
	if err := devA.Up(); err != nil {
		fmt.Println("FAIL Up A:", err)
		os.Exit(1)
	}
	if err := devB.Up(); err != nil {
		fmt.Println("FAIL Up B:", err)
		os.Exit(1)
	}
	fmt.Println("HANDSHAKE_BEFORE:", handshakeSeconds(devA))

	aIP := allowedIPOf(uapiB)
	bIP := allowedIPOf(uapiA)

	// A sends an echo request to B. Writing into A's TUN is the same entry point
	// the kernel uses, so this exercises routing → encryption → UDP → decryption
	// → B's TUN.
	request := icmpEcho(aIP, bIP, 0x41, "agentspace-net-proof")
	go func() { tunA.out <- request }()

	var received []byte
	select {
	case received = <-tunB.in:
		fmt.Println("B_RECEIVED:", describe(received))
	case <-time.After(10 * time.Second):
		fmt.Println("FAIL: B received nothing within 10s")
		fmt.Println("HANDSHAKE_A:", handshakeText(devA))
		os.Exit(1)
	}

	// B answers, so the reverse direction is proven too. The reply must swap the
	// addresses as well as flip the ICMP type: reusing the received packet as-is
	// sends it to the address that just sent it, which is why the first version
	// of this harness showed a passing forward direction and no reply.
	reply := make([]byte, len(received))
	copy(reply, received)
	copy(reply[12:16], bIP)
	copy(reply[16:20], aIP)
	reply[20] = 0 // echo reply
	reply[22], reply[23] = 0, 0
	binary.BigEndian.PutUint16(reply[22:], checksum(reply[20:]))
	binary.BigEndian.PutUint16(reply[10:], 0)
	binary.BigEndian.PutUint16(reply[10:], checksum(reply[:20]))
	go func() { tunB.out <- reply }()

	select {
	case back := <-tunA.in:
		fmt.Println("A_RECEIVED:", describe(back))
	case <-time.After(10 * time.Second):
		fmt.Println("FAIL: A received no reply within 10s")
		os.Exit(1)
	}

	time.Sleep(300 * time.Millisecond)
	hsA := handshakeSeconds(devA)
	hsB := handshakeSeconds(devB)
	fmt.Println("HANDSHAKE_A_SEC:", hsA, "AGE:", time.Now().Unix()-hsA)
	fmt.Println("HANDSHAKE_B_SEC:", hsB, "AGE:", time.Now().Unix()-hsB)
	fmt.Println("STATE_A:", handshakeText(devA))
	fmt.Println("STATE_B:", handshakeText(devB))
	if hsA == 0 || hsB == 0 {
		fmt.Println("FAIL: a device reports no handshake")
		os.Exit(1)
	}
	if time.Now().Unix()-hsA > 30 {
		fmt.Println("FAIL: handshake is stale")
		os.Exit(1)
	}
	fmt.Println("RESULT: PASS — real wireguard-go handshake and bidirectional data using the product's generated configuration")
}

func (t *fakeTUN) Flush() error { return nil }

func (t *fakeTUN) BatchSize() int { return 1 }
