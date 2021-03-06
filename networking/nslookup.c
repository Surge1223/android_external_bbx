/* vi: set sw=4 ts=4: */
/*
 * Mini nslookup implementation for bbx
 *
 * Copyright (C) 1999,2000 by Lineo, inc. and John Beppu
 * Copyright (C) 1999,2000,2001 by John Beppu <beppu@codepoet.org>
 *
 * Correct default name server display and explicit name server option
 * added by Ben Zeckel <bzeckel@hmc.edu> June 2001
 *
 * Licensed under GPLv2 or later, see file LICENSE in this source tree.
 */

//usage:#define nslookup_trivial_usage
//usage:       "[HOST] [SERVER]"
//usage:#define nslookup_full_usage "\n\n"
//usage:       "Query the nameserver for the IP address of the given HOST\n"
//usage:       "optionally using a specified DNS server"
//usage:
//usage:#define nslookup_example_usage
//usage:       "$ nslookup localhost\n"
//usage:       "Server:     default\n"
//usage:       "Address:    default\n"
//usage:       "\n"
//usage:       "Name:       debian\n"
//usage:       "Address:    127.0.0.1\n"

#include <resolv.h>
#include "libbb.h"

#ifdef ANDROID
# include <netinet/in.h>
# if ENABLE_FEATURE_IPV6
#  include <netinet/in6.h>
# endif
# define ANDROID_CHANGES
# ifdef ANDROID
#  include <arpa/nameser.h>
#  include <dns/include/resolv_private.h>
#  include <dns/resolv/res_private.h>
# else
#  include <arpa_nameser.h>
#  include <private/resolv_private.h>
#  include <netbsd/resolv/res_private.h>
# endif

static struct __res_state res_st;
struct __res_state * __res_state(void)
{
	return &res_st;
}
#endif

#define EXT(res) ((&res)->_u._ext)

/*
 * I'm only implementing non-interactive mode;
 * I totally forgot nslookup even had an interactive mode.
 *
 * This applet is the only user of res_init(). Without it,
 * you may avoid pulling in _res global from libc.
 */

/* Examples of 'standard' nslookup output
 * $ nslookup yahoo.com
 * Server:         128.193.0.10
 * Address:        128.193.0.10#53
 *
 * Non-authoritative answer:
 * Name:   yahoo.com
 * Address: 216.109.112.135
 * Name:   yahoo.com
 * Address: 66.94.234.13
 *
 * $ nslookup 204.152.191.37
 * Server:         128.193.4.20
 * Address:        128.193.4.20#53
 *
 * Non-authoritative answer:
 * 37.191.152.204.in-addr.arpa     canonical name = 37.32-27.191.152.204.in-addr.arpa.
 * 37.32-27.191.152.204.in-addr.arpa       name = zeus-pub2.kernel.org.
 *
 * Authoritative answers can be found from:
 * 32-27.191.152.204.in-addr.arpa  nameserver = ns1.kernel.org.
 * 32-27.191.152.204.in-addr.arpa  nameserver = ns2.kernel.org.
 * 32-27.191.152.204.in-addr.arpa  nameserver = ns3.kernel.org.
 * ns1.kernel.org  internet address = 140.211.167.34
 * ns2.kernel.org  internet address = 204.152.191.4
 * ns3.kernel.org  internet address = 204.152.191.36
 */

static int print_host(const char *hostname, const char *header)
{
	/* We can't use xhost2sockaddr() - we want to get ALL addresses,
	 * not just one */
	struct addrinfo *result = NULL;
	int rc;
	struct addrinfo hint;

	memset(&hint, 0 , sizeof(hint));
	/* hint.ai_family = AF_UNSPEC; - zero anyway */
	/* Needed. Or else we will get each address thrice (or more)
	 * for each possible socket type (tcp,udp,raw...): */
	hint.ai_socktype = SOCK_STREAM;
	// hint.ai_flags = AI_CANONNAME;
	rc = getaddrinfo(hostname, NULL /*service*/, &hint, &result);

	if (rc == 0) {
		struct addrinfo *cur = result;
		unsigned cnt = 0;

		printf("%-10s %s\n", header, hostname);
		// puts(cur->ai_canonname); ?
		while (cur) {
			char *dotted, *revhost;
			dotted = xmalloc_sockaddr2dotted_noport(cur->ai_addr);
			revhost = xmalloc_sockaddr2hostonly_noport(cur->ai_addr);

			printf("Address %u: %s%c", ++cnt, dotted, revhost ? ' ' : '\n');
			if (revhost) {
				puts(revhost);
				if (ENABLE_FEATURE_CLEAN_UP)
					free(revhost);
			}
			if (ENABLE_FEATURE_CLEAN_UP)
				free(dotted);
			cur = cur->ai_next;
		}
	} else {
#if ENABLE_VERBOSE_RESOLUTION_ERRORS
		bb_error_msg("can't resolve '%s': %s", hostname, gai_strerror(rc));
#else
		bb_error_msg("can't resolve '%s'", hostname);
#endif
	}
	if (ENABLE_FEATURE_CLEAN_UP && result)
		freeaddrinfo(result);
	return (rc != 0);
}

/* lookup the default nameserver and display it */
static void server_print(void)
{
	char *server;
	struct sockaddr *sa = NULL;

#if ENABLE_FEATURE_IPV6
# ifdef ANDROID
	if (EXT(_res).ext)
		sa = (struct sockaddr*) &EXT(_res).ext->nsaddrs[0];
# else
    sa = (struct sockaddr*)_res._u._ext.nsaddrs[0];
# endif

	if (!sa)
#endif
		sa = (struct sockaddr*) &_res.nsaddr_list[0];
	server = xmalloc_sockaddr2dotted_noport(sa);

	print_host(server, "Server:");
	if (ENABLE_FEATURE_CLEAN_UP)
		free(server);
	bb_putchar('\n');
}

/* alter the global _res nameserver structure to use
   an explicit dns server instead of what is in /etc/resolv.conf */
static void set_default_dns(const char *server)
{
	len_and_sockaddr *lsa;

	if (!server)
		return;

	/* NB: this works even with, say, "[::1]:53"! :) */
	lsa = xhost2sockaddr(server, 53);

	if (lsa->u.sa.sa_family == AF_INET) {
		_res.nscount = 1;
		/* struct copy */
		_res.nsaddr_list[0] = lsa->u.sin;
	}

#if ENABLE_FEATURE_IPV6
	/* Hoped libc can cope with IPv4 address there too.
	 * No such luck, glibc 2.4 segfaults even with IPv6,
	 * maybe I misunderstand how to make glibc use IPv6 addr?
	 * (uclibc 0.9.31+ should work) */
	if (lsa->u.sa.sa_family == AF_INET6) {
		// glibc neither SEGVs nor sends any dgrams with this
		// (strace shows no socket ops):
		//_res.nscount = 0;
	#ifdef ANDROID
		if (EXT(_res).ext) {
			EXT(_res).nscount = 1;
			memcpy(&EXT(_res).ext->nsaddrs[0].sin6, &lsa->u.sin6,
				sizeof(struct sockaddr_in6));
		}
	#else
		/* store a pointer to part of malloc'ed lsa */
		_res._u._ext.nscount = 1;
		_res._u._ext.nsaddrs[0] = &lsa->u.sin6;
		/* must not free(lsa)! */
	#endif
	}
#endif
}

int nslookup_main(int argc, char **argv) MAIN_EXTERNALLY_VISIBLE;
int nslookup_main(int argc, char **argv)
{
	/* We allow 1 or 2 arguments.
	 * The first is the name to be looked up and the second is an
	 * optional DNS server with which to do the lookup.
	 * More than 3 arguments is an error to follow the pattern of the
	 * standard nslookup */
	if (!argv[1] || argv[1][0] == '-' || argc > 3)
		bb_show_usage();

	/* initialize DNS structure _res used in printing the default
	 * name server and in the explicit name server option feature. */
	res_init();

#ifdef ANDROID
	res_ninit(&_res);
#endif

	/* rfc2133 says this enables IPv6 lookups */
	/* (but it also says "may be enabled in /etc/resolv.conf") */
	/*_res.options |= RES_USE_INET6;*/

	set_default_dns(argv[2]);

	server_print();

	/* getaddrinfo and friends are free to request a resolver
	 * reinitialization. Just in case, set_default_dns() again
	 * after getaddrinfo (in server_print). This reportedly helps
	 * with bug 675 "nslookup does not properly use second argument"
	 * at least on Debian Wheezy and Openwrt AA (eglibc based).
	 */
	set_default_dns(argv[2]);

	return print_host(argv[1], "Name:");
}
