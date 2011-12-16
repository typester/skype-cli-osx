LDFLAGS=-framework Foundation

all: skype-cli

skype-cli: skype.o
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.m
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o
	rm -f skype-cli
