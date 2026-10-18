/*
 * ddtool: small helpers the DeskDroid installer runs from nativeLibraryDir.
 *
 *   ddtool zstdcat <file>
 *       Decompress a .zst file to stdout (the app reads the tar stream).
 *   ddtool verify <public-key> <file> <file.minisig>
 *       Check a minisign signature. <public-key> is the base64 line of a
 *       minisign .pub file. Exit 0 and print the trusted comment if valid.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "monocypher.h"
#include "monocypher-ed25519.h"
#include "zstd.h"

static int fail(const char *what, const char *detail)
{
	fprintf(stderr, "ddtool: %s%s%s\n", what, detail ? ": " : "", detail ? detail : "");
	return 1;
}

static int zstdcat(const char *path)
{
	FILE *in = fopen(path, "rb");
	if (!in)
		return fail(path, strerror(errno));

	size_t in_size = ZSTD_DStreamInSize(), out_size = ZSTD_DStreamOutSize();
	void *in_buf = malloc(in_size), *out_buf = malloc(out_size);
	ZSTD_DCtx *dctx = ZSTD_createDCtx();
	if (!in_buf || !out_buf || !dctx)
		return fail("out of memory", NULL);
	/* Images are made with --long=27; allow windows up to 2 GB. */
	ZSTD_DCtx_setParameter(dctx, ZSTD_d_windowLogMax, 31);

	size_t n, last = 0;
	while ((n = fread(in_buf, 1, in_size, in)) > 0) {
		ZSTD_inBuffer input = { in_buf, n, 0 };
		while (input.pos < input.size) {
			ZSTD_outBuffer output = { out_buf, out_size, 0 };
			last = ZSTD_decompressStream(dctx, &output, &input);
			if (ZSTD_isError(last))
				return fail("corrupt zstd data", ZSTD_getErrorName(last));
			if (fwrite(out_buf, 1, output.pos, stdout) != output.pos)
				return fail("write failed", strerror(errno));
		}
	}
	if (ferror(in))
		return fail(path, strerror(errno));
	if (last != 0)
		return fail("truncated zstd data", path);
	if (fflush(stdout) != 0)
		return fail("write failed", strerror(errno));
	ZSTD_freeDCtx(dctx);
	fclose(in);
	return 0;
}

/* Standard base64 decode; returns decoded length or -1. */
static long b64decode(const char *s, uint8_t *out, size_t max)
{
	static const char *alphabet =
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	uint32_t acc = 0;
	int bits = 0;
	size_t len = 0;
	for (; *s && *s != '=' && *s != '\n' && *s != '\r'; s++) {
		const char *p = strchr(alphabet, *s);
		if (!p || !*s)
			return -1;
		acc = (acc << 6) | (uint32_t)(p - alphabet);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			if (len >= max)
				return -1;
			out[len++] = (uint8_t)(acc >> bits);
		}
	}
	return (long)len;
}

/* Reads line `index` (0-based) of a small text file into buf, without the newline. */
static int read_line(FILE *f, int index, char *buf, size_t size)
{
	rewind(f);
	for (int i = 0; i <= index; i++) {
		if (!fgets(buf, (int)size, f))
			return -1;
	}
	buf[strcspn(buf, "\r\n")] = 0;
	return 0;
}

static int verify(const char *pubkey_b64, const char *path, const char *sig_path)
{
	uint8_t pk[2 + 8 + 32], sig[2 + 8 + 64], global_sig[64];
	if (b64decode(pubkey_b64, pk, sizeof pk) != sizeof pk || memcmp(pk, "Ed", 2) != 0)
		return fail("bad public key", NULL);

	FILE *sf = fopen(sig_path, "r");
	if (!sf)
		return fail(sig_path, strerror(errno));
	char line[2048], trusted[1024];
	if (read_line(sf, 1, line, sizeof line) < 0 ||
	    b64decode(line, sig, sizeof sig) != sizeof sig)
		return fail("bad signature file", sig_path);
	if (read_line(sf, 2, line, sizeof line) < 0 ||
	    strncmp(line, "trusted comment: ", 17) != 0)
		return fail("bad signature file", "no trusted comment");
	snprintf(trusted, sizeof trusted, "%s", line + 17);
	if (read_line(sf, 3, line, sizeof line) < 0 ||
	    b64decode(line, global_sig, sizeof global_sig) != sizeof global_sig)
		return fail("bad signature file", "no global signature");
	fclose(sf);

	if (memcmp(sig + 2, pk + 2, 8) != 0)
		return fail("signed with a different key", NULL);
	int prehashed;
	if (memcmp(sig, "ED", 2) == 0)
		prehashed = 1;
	else if (memcmp(sig, "Ed", 2) == 0)
		prehashed = 0;
	else
		return fail("unsupported signature algorithm", NULL);
	if (!prehashed)
		return fail("legacy (non-prehashed) signatures are not accepted", NULL);

	/* "ED": the signature covers BLAKE2b-512 of the file. */
	FILE *in = fopen(path, "rb");
	if (!in)
		return fail(path, strerror(errno));
	crypto_blake2b_ctx ctx;
	crypto_blake2b_init(&ctx, 64);
	static uint8_t buf[1 << 16];
	size_t n;
	while ((n = fread(buf, 1, sizeof buf, in)) > 0)
		crypto_blake2b_update(&ctx, buf, n);
	if (ferror(in))
		return fail(path, strerror(errno));
	fclose(in);
	uint8_t hash[64];
	crypto_blake2b_final(&ctx, hash);

	if (crypto_ed25519_check(sig + 10, pk + 10, hash, sizeof hash) != 0)
		return fail("signature does not match", path);

	/* The global signature covers signature || trusted comment. */
	size_t tlen = strlen(trusted);
	uint8_t *msg = malloc(64 + tlen);
	if (!msg)
		return fail("out of memory", NULL);
	memcpy(msg, sig + 10, 64);
	memcpy(msg + 64, trusted, tlen);
	int bad = crypto_ed25519_check(global_sig, pk + 10, msg, 64 + tlen);
	free(msg);
	if (bad)
		return fail("trusted comment signature does not match", NULL);

	printf("%s\n", trusted);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "zstdcat") == 0)
		return zstdcat(argv[2]);
	if (argc == 5 && strcmp(argv[1], "verify") == 0)
		return verify(argv[2], argv[3], argv[4]);
	fprintf(stderr,
		"usage: ddtool zstdcat <file>\n"
		"       ddtool verify <public-key> <file> <file.minisig>\n");
	return 2;
}
