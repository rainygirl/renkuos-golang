// Copyright 2014 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "textflag.h"

TEXT _rt0_arm64_haiku(SB),NOSPLIT,$0
	JMP	runtime·rt0_go(SB)

TEXT _rt0_arm64_haiku_lib(SB),NOSPLIT,$0
	JMP	_rt0_arm64_lib(SB)
