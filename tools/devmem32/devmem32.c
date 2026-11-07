// SPDX-License-Identifier: MIT
/*
 * devmem32 : lecture / écriture d'un registre 32 bits par /dev/mem (mmap),
 * pour le debug matériel du LG G3 (le busybox d'Alpine n'a pas « devmem »).
 *
 *   devmem32 ADRESSE            lit et affiche 0xXXXXXXXX
 *   devmem32 ADRESSE VALEUR     écrit VALEUR (puis relit)
 *   devmem32 ADRESSE N --dump   lit N mots consécutifs
 *
 * Adresses et valeurs en décimal ou en 0x... ; adresse alignée sur 4.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static int parse(const char *s, uint64_t *out)
{
	char *end;

	errno = 0;
	*out = strtoull(s, &end, 0);
	return (errno || *end || end == s) ? -1 : 0;
}

int main(int argc, char **argv)
{
	uint64_t addr, val = 0, count = 1;
	int write = 0, dump = 0;
	long page = sysconf(_SC_PAGESIZE);

	if (argc < 2 || argc > 4 || parse(argv[1], &addr) || (addr & 3)) {
		fprintf(stderr, "usage : %s ADRESSE [VALEUR | N --dump]\n", argv[0]);
		return 2;
	}
	if (argc == 4 && !strcmp(argv[3], "--dump")) {
		if (parse(argv[2], &count) || !count || count > 4096) {
			fprintf(stderr, "N invalide\n");
			return 2;
		}
		dump = 1;
	} else if (argc == 3) {
		if (parse(argv[2], &val) || val > 0xffffffffULL) {
			fprintf(stderr, "VALEUR invalide\n");
			return 2;
		}
		write = 1;
	} else if (argc != 2) {
		fprintf(stderr, "usage : %s ADRESSE [VALEUR | N --dump]\n", argv[0]);
		return 2;
	}

	int fd = open("/dev/mem", (write ? O_RDWR : O_RDONLY) | O_SYNC);
	if (fd < 0) {
		perror("/dev/mem");
		return 1;
	}

	uint64_t base = addr & ~((uint64_t)page - 1);
	size_t len = (addr - base) + count * 4;
	len = (len + page - 1) & ~((size_t)page - 1);
	void *map = mmap(NULL, len, write ? PROT_READ | PROT_WRITE : PROT_READ,
			 MAP_SHARED, fd, (off_t)base);
	if (map == MAP_FAILED) {
		perror("mmap");
		close(fd);
		return 1;
	}

	volatile uint32_t *reg = (volatile uint32_t *)((char *)map + (addr - base));
	if (write)
		*reg = (uint32_t)val;

	if (dump) {
		for (uint64_t i = 0; i < count; i++)
			printf("0x%08llx: 0x%08x\n",
			       (unsigned long long)(addr + i * 4), reg[i]);
	} else {
		printf("0x%08x\n", *reg);
	}

	munmap(map, len);
	close(fd);
	return 0;
}
