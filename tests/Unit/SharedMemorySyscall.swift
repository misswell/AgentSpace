import Darwin

/// `shm_open` is marked unavailable to Swift on macOS even though the symbol has
/// been in libSystem the whole time, which is why the allocator reaches for it by
/// name rather than by import. A test that could not call it could not prove
/// anything about it either, so it uses the same door.
@_silgen_name("shm_open")
internal func shmOpen(_ name: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32

/// Open by name with the flags the allocator uses.
///
/// Returns the descriptor *and* the `errno` read on the line after the syscall
/// returned, before anything else — including the string building at a call site —
/// can run over it. That is how a name-length bug gets logged as a permissions one.
///
/// `errno` is zeroed first here and only here. The allocator must not do it — a
/// caller that clears the value before the syscall is a caller that cannot tell
/// `EACCES` from "nothing ran" — but a test asserting *success* needs a zero it can
/// believe, because the kernel leaves the previous failure sitting in `errno` when
/// a call works.
internal func shmOpen(_ name: String, _ flags: Int32 = O_RDWR, _ mode: mode_t = S_IRUSR | S_IWUSR) -> (descriptor: Int32, code: Int32) {
    errno = 0
    var code: Int32 = 0
    let descriptor = name.withCString { address in
        let opened = shmOpen(address, flags, mode)
        code = errno
        return opened
    }
    return (descriptor, code)
}

/// Whether a descriptor still refers to something: 0 while it does, -1/EBADF once
/// whatever owned it has released it.
internal func sharedMemoryDescriptorIsOpen(_ descriptor: Int32) -> Bool {
    var info = stat()
    return fstat(descriptor, &info) == 0
}
