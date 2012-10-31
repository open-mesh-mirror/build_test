#ifndef _LINUX_STDDEF_H
#define _LINUX_STDDEF_H

#include <linux/compiler.h>

enum {
	false	= 0,
	true	= 1
};

#undef offsetof
#define offsetof(TYPE, MEMBER) ((size_t) &((TYPE *)0)->MEMBER)

#endif
