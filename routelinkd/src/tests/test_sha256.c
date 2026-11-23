#include "t.h"

#include "core/sha256.h"

static void hex(const uint8_t *d, size_t n, char *out)
{
	for (size_t i = 0; i < n; i++)
		sprintf(out + 2 * i, "%02x", d[i]);
}

static void sha(const char *msg, size_t len, char out[65])
{
	uint8_t d[RL_SHA256_LEN];
	rl_sha256(msg, len, d);
	hex(d, sizeof(d), out);
}

/* FIPS 180-2 examples. */
static void test_sha256_vectors(void)
{
	char out[65];
	sha("abc", 3, out);
	T_EQ_STR(out, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	sha("", 0, out);
	T_EQ_STR(out, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
	const char *two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
	sha(two, strlen(two), out);
	T_EQ_STR(out, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
}

/* A million 'a's through many small updates crosses every block boundary case. */
static void test_sha256_streaming(void)
{
	rl_sha256_ctx c;
	char chunk[1000];
	memset(chunk, 'a', sizeof(chunk));
	rl_sha256_init(&c);
	for (int i = 0; i < 1000; i++)
		rl_sha256_update(&c, chunk, sizeof(chunk));
	uint8_t d[RL_SHA256_LEN];
	char out[65];
	rl_sha256_final(&c, d);
	hex(d, sizeof(d), out);
	T_EQ_STR(out, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
}

/* RFC 4231 test cases 1, 2 and 6 (key longer than a block). */
static void test_hmac_vectors(void)
{
	uint8_t d[RL_SHA256_LEN], key[131];
	char out[65];

	memset(key, 0x0b, 20);
	rl_hmac_sha256(key, 20, "Hi There", 8, d);
	hex(d, sizeof(d), out);
	T_EQ_STR(out, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");

	const char *msg = "what do ya want for nothing?";
	rl_hmac_sha256("Jefe", 4, msg, strlen(msg), d);
	hex(d, sizeof(d), out);
	T_EQ_STR(out, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");

	memset(key, 0xaa, sizeof(key));
	const char *big = "Test Using Larger Than Block-Size Key - Hash Key First";
	rl_hmac_sha256(key, sizeof(key), big, strlen(big), d);
	hex(d, sizeof(d), out);
	T_EQ_STR(out, "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
}

/* RFC 4648 examples. */
static void test_base64(void)
{
	char out[16];
	const char *in[] = { "", "f", "fo", "foo", "foob", "fooba", "foobar" };
	const char *want[] = { "", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy" };
	for (int i = 0; i < 7; i++) {
		size_t n = rl_base64((const uint8_t *)in[i], strlen(in[i]), out, sizeof(out));
		T_EQ_STR(out, want[i]);
		T_EQ_U64(n, strlen(want[i]));
	}
	T_EQ_U64(rl_base64((const uint8_t *)"foobar", 6, out, 8), 0);
}

int main(void)
{
	T_RUN(test_sha256_vectors);
	T_RUN(test_sha256_streaming);
	T_RUN(test_hmac_vectors);
	T_RUN(test_base64);
	T_DONE();
}
