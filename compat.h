/* Compatibility shim for kernels lacking kmalloc_obj/kzalloc_obj */
#ifndef kmalloc_obj
#define kmalloc_obj(x) kmalloc(sizeof(x), GFP_KERNEL)
#endif
#ifndef kzalloc_obj
#define kzalloc_obj(x) kzalloc(sizeof(x), GFP_KERNEL)
#endif
