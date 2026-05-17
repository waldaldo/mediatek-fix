/* Compatibility shims for out-of-tree builds.
 *
 * kmalloc_obj/kzalloc_obj were introduced in kernel 6.x; older headers shipped
 * with some distros may lack them.  The downloaded btintel.h/btmtk.h headers
 * may reference these symbols, so the fallback must be provided before any
 * bluetooth subsystem header is included (via -include compat.h in EXTRA_CFLAGS).
 */
#ifndef kmalloc_obj
#define kmalloc_obj(type) kmalloc(sizeof(type), GFP_KERNEL)
#endif
#ifndef kzalloc_obj
#define kzalloc_obj(type) kzalloc(sizeof(type), GFP_KERNEL)
#endif
