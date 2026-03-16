obj-m := btusb.o
KDIR := /lib/modules/$(shell uname -r)/build
EXTRA_CFLAGS := -I$(PWD) -include $(PWD)/compat.h

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
