TARGET := linkbackd
OBJS := linkbackd.o

CFLAGS += -Wall -O2
LIBS := -luci

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(TARGET) $(LDFLAGS) $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o $(TARGET)

.PHONY: all clean
