// Copyright 2026 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include <TLS.h>
#include <stdint.h>
#include "libcgo.h"

// On Haiku/arm64 TPIDR_EL0 points at the calling thread's TLS slot array,
// so one slot from tls_allocate() is at the same offset from TPIDR_EL0 in
// every thread, and runtime.load_g/save_g use that offset (runtime.tls_g).
// ELF initial-exec TLS is not an option: Haiku's runtime loader has no
// static TLS block.
static void
inittls(void **tlsg, void **tlsbase)
{
	int32 slot;

	slot = tls_allocate();
	if (slot < 0) {
		fatalf("inittls: tls_allocate failed: %d", (int)slot);
	}
	*tlsg = (void*)((uintptr_t)slot * sizeof(void*));
}

void (*x_cgo_inittls)(void **tlsg, void **tlsbase) = inittls;
