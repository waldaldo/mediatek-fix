obj-m := btusb.o
KDIR := /lib/modules/$(shell uname -r)/build
EXTRA_CFLAGS := -I$(CURDIR) -include $(CURDIR)/compat.h

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
