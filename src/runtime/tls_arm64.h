// Copyright 2015 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#ifdef GOOS_android
#define TLS_linux
#define TLSG_IS_VARIABLE
#endif
#ifdef GOOS_linux
#define TLS_linux
#endif
#ifdef TLS_linux
#define MRS_TPIDR_R0 WORD $0xd53bd040 // MRS TPIDR_EL0, R0
#endif

#ifdef GOOS_darwin
#define TLS_darwin
#endif
#ifdef GOOS_ios
#define TLS_darwin
#endif
#ifdef TLS_darwin
#define TLSG_IS_VARIABLE
#define MRS_TPIDR_R0 WORD $0xd53bd060 // MRS TPIDRRO_EL0, R0
#endif

#ifdef GOOS_freebsd
#define MRS_TPIDR_R0 WORD $0xd53bd040 // MRS TPIDR_EL0, R0
#endif

#ifdef GOOS_netbsd
#define MRS_TPIDR_R0 WORD $0xd53bd040 // MRS TPIDRRO_EL0, R0
#endif

#ifdef GOOS_openbsd
#define MRS_TPIDR_R0 WORD $0xd53bd040 // MRS TPIDR_EL0, R0
#endif

#ifdef GOOS_haiku
// TPIDR_EL0 points at Haiku's own TLS slot array (void* tls[TLS_MAX_KEYS],
// see src/system/libroot/os/arch/arm64/tls.c), not at an ELF TLS block.
// g lives in slot 62 (tls_g is a variable, see tls_arm64.s), the same
// slot haiku/amd64 uses (cmd/link Tlsoffset = (64-2)*8). Unlike linux,
// g is kept there even without cgo: Go code calls into libroot for
// every system call, so a signal can interrupt libc code at a point
// where R28 does not hold g.
#define MRS_TPIDR_R0 WORD $0xd53bd040 // MRS TPIDR_EL0, R0
#define TLSG_IS_VARIABLE
#endif

#ifdef GOOS_windows
#define TLS_windows
#endif
#ifdef TLS_windows
#define TLSG_IS_VARIABLE
#define MRS_TPIDR_R0 MOVD R18_PLATFORM, R0
#endif

// Define something that will break the build if
// the GOOS is unknown.
#ifndef MRS_TPIDR_R0
#define MRS_TPIDR_R0 unknown_TLS_implementation_in_tls_arm64_h
#endif
