/*
 * Wireless stations of the AP role: the latest sample per MAC, a ring of recent samples for the live
 * tier, association tracking (connect / disconnect), minute and hour signal aggregation into 32-byte
 * records (signal.minute, signal.hour), signal history queries, and channel busy time from survey
 * counter deltas.
 */
#ifndef RL_WIFI_H
#define RL_WIFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"
#include "core/series.h"
#include "core/timeutil.h"

#define RL_WIFI_RING 300       /* live points per station: 5 min at 1 s, 50 min at 10 s */
#define RL_WIFI_LIVE_RANGE 600 /* signal queries starting within this many seconds may use the ring */
#define RL_WIFI_FORGET 600     /* a station that left is dropped this long after (once its buckets closed) */

typedef enum {
	RL_WIFI_MODE_UNKNOWN,
	RL_WIFI_MODE_LEGACY,
	RL_WIFI_MODE_HT,
	RL_WIFI_MODE_VHT,
	RL_WIFI_MODE_HE,
} rl_wifi_mode;

/* rl_sta_sample.has: fields the driver reported */
enum {
	RL_STA_SIGNAL = 1 << 0,
	RL_STA_SIGNAL_AVG = 1 << 1,
	RL_STA_INACTIVE = 1 << 2,
	RL_STA_CONNECTED = 1 << 3,
	RL_STA_RX_RATE = 1 << 4,
	RL_STA_TX_RATE = 1 << 5,
	RL_STA_RX_MCS = 1 << 6,
	RL_STA_TX_MCS = 1 << 7,
	RL_STA_RX_NSS = 1 << 8,
	RL_STA_TX_NSS = 1 << 9,
	RL_STA_BYTES = 1 << 10,
	RL_STA_PACKETS = 1 << 11,
	RL_STA_RETRIES = 1 << 12,
	RL_STA_FAILED = 1 << 13,
	RL_STA_WIDTH = 1 << 14,
	RL_STA_MODE = 1 << 15,
	RL_STA_FLAGS = 1 << 16, /* authorized is valid */
};

/*
 * One station from an nl80211 station dump. MCS and NSS are per stream for every mode (HT MCS 15 is
 * reported as MCS 7 with 2 streams).
 */
typedef struct {
	rl_mac mac;
	int ifindex;
	uint32_t has;
	bool authorized;
	int8_t signal, signal_avg; /* dBm */
	uint32_t inactive_ms, connected_sec;
	uint32_t rx_rate, tx_rate; /* kbit/s */
	uint8_t rx_mcs, tx_mcs, rx_nss, tx_nss;
	uint16_t width;    /* MHz, from the tx rate */
	rl_wifi_mode mode; /* from the tx rate */
	uint64_t rx_bytes, tx_bytes, rx_packets, tx_packets;
	uint32_t tx_retries, tx_failed;
} rl_sta_sample;

/* Values present in a signal record, live point or query point; 0 = no data. */
enum { RL_SIG_F_SIGNAL = 1, RL_SIG_F_TX_RATE = 2, RL_SIG_F_COUNTERS = 4, RL_SIG_F_RX_RATE = 8 };

/*
 * Signal record (signal.minute / signal.hour), little-endian:
 *   0 u32 ts (bucket start)   4 u16 dev   6 u8 flags   7 s8 max_signal   8 s8 avg_signal   9 s8 min_signal
 *  10 u16 samples (with a signal)   12 u32 avg_tx_rate   16 u32 avg_rx_rate (kbit/s)
 *  20 u32 tx_retries   24 u32 tx_failed (increase within the bucket)   28 u16 freq (MHz, last sample)
 *  30 u16 rate_samples (weight of the rate averages)
 * A bucket may have several records for a device (a partial minute written before a shutdown, a partial
 * hour written when the module stopped); readers merge them weighted by samples / rate_samples.
 */
typedef struct {
	int64_t ts;
	uint16_t dev;
	uint8_t flags;
	int8_t avg_signal, min_signal, max_signal;
	uint16_t samples, rate_samples;
	uint32_t avg_tx_rate, avg_rx_rate;
	uint32_t tx_retries, tx_failed;
	uint16_t freq;
} rl_sig_rec;

#define RL_SIG_KIND_MINUTE 0x5301
#define RL_SIG_KIND_HOUR 0x5302

void rl_sig_encode(const rl_sig_rec *r, uint8_t out[RL_SERIES_REC_SIZE]);
void rl_sig_decode(const uint8_t in[RL_SERIES_REC_SIZE], rl_sig_rec *r);

/* Open bucket of one tier (also used to merge records); all zero = empty. */
typedef struct {
	int64_t start; /* 0 = nothing open */
	uint8_t flags; /* RL_SIG_F_* seen so far */
	uint32_t samples, tx_n, rx_n;
	int64_t sum_signal;
	int8_t min_signal, max_signal;
	uint64_t sum_tx, sum_rx, retries, failed;
	uint32_t freq;
} rl_sig_acc;

typedef struct {
	uint32_t ts;
	uint32_t tx_rate, rx_rate;
	uint16_t retries, failed; /* increase since the previous point (saturated) */
	int8_t signal;
	uint8_t flags; /* RL_SIG_F_* */
} rl_live_pt;

typedef struct {
	/* read-only for callers */
	rl_mac mac;
	uint16_t dev;
	int ifindex;
	char ifname[16];
	uint32_t freq; /* MHz of its interface */
	bool associated;
	int64_t updated; /* latest sample, 0 = none yet */
	int64_t changed; /* latest association change */
	rl_sta_sample s; /* latest sample */

	/* internal */
	bool seen, have_prev;
	uint32_t prev_retries, prev_failed;
	rl_sig_acc acc[2]; /* minute, hour */
	rl_live_pt *ring;
	uint16_t ring_head, ring_n;
} rl_wifi_sta;

/* A closed (or flushed) signal record; tier is RL_TIER_MINUTE or RL_TIER_HOUR. */
typedef void (*rl_sig_rec_cb)(rl_tier tier, const uint8_t rec[RL_SERIES_REC_SIZE], void *ctx);
/* A station connected (st->freq: its new interface) or disconnected (st->freq: the interface it left). */
typedef void (*rl_wifi_assoc_cb)(const rl_wifi_sta *st, bool connected, void *ctx);

typedef struct rl_wifi rl_wifi;

rl_wifi *rl_wifi_new(rl_sig_rec_cb on_rec, rl_wifi_assoc_cb on_assoc, void *ctx);
void rl_wifi_free(rl_wifi *w);

/*
 * A station dump: begin, one update per station (any interface), end. The first complete dump (and the
 * first after rl_wifi_clear) is a baseline: stations found associated there raise no events.
 * Call rl_wifi_tick(now) before a dump so that older buckets are closed first.
 * Stations whose flags say they are not authorized yet (WPA handshake running) count as absent.
 */
void rl_wifi_begin(rl_wifi *w);
rl_wifi_sta *rl_wifi_update(rl_wifi *w, const rl_sta_sample *s, uint16_t dev, const char *ifname, uint32_t freq,
			    int64_t now);
/* complete: every AP interface was dumped, so associated stations that were not reported have left. */
void rl_wifi_end(rl_wifi *w, int64_t now, bool complete);
/* nl80211 DEL_STATION: the station left ifindex (ignored when it is associated elsewhere by now). */
void rl_wifi_disassoc(rl_wifi *w, const rl_mac *mac, int ifindex, int64_t now);

/* Closes minute/hour buckets that ended at or before now (in ts order); forgets long-gone stations. */
void rl_wifi_tick(rl_wifi *w, int64_t now);
/*
 * Emits the open minute buckets (and with hour, the hour buckets) as partial records and empties them;
 * the buckets stay open. Minutes before a commit that may be the last one; hours too when the module
 * stops (a restart of the daemon rebuilds the open hour from the minute file instead, rl_wifi_recover).
 */
void rl_wifi_flush(rl_wifi *w, bool hour);
/* Drops open buckets and live rings (data reset, clock set). Association state stays. */
void rl_wifi_reset_data(rl_wifi *w);
/* Forgets every station (device indexes reset); the next complete dump is a baseline again. */
void rl_wifi_clear(rl_wifi *w);

rl_wifi_sta *rl_wifi_find(const rl_wifi *w, const rl_mac *mac);
rl_wifi_sta *rl_wifi_find_dev(const rl_wifi *w, uint16_t dev);
size_t rl_wifi_count(const rl_wifi *w);
rl_wifi_sta *rl_wifi_at(const rl_wifi *w, size_t i);
/* Associated stations on an interface. */
size_t rl_wifi_count_on(const rl_wifi *w, int ifindex);

/* Live points with start <= ts < end, oldest first; returns how many were written (at most max). */
size_t rl_wifi_live(const rl_wifi_sta *st, int64_t start, int64_t end, rl_live_pt *out, size_t max);
/* The open bucket of a tier as a record; false when nothing is open. */
bool rl_wifi_open_rec(const rl_wifi_sta *st, rl_tier tier, rl_sig_rec *out);

/* Maps a device index to its MAC; false for unknown devices. */
typedef bool (*rl_wifi_mac_fn)(uint16_t dev, rl_mac *out, void *ctx);

/*
 * Restart recovery (like core/recover for traffic): writes the hour records of hours that ended while
 * nothing was recording, summed from signal.minute, and rebuilds the open hour buckets from the minute
 * records of the current hour (creating not-associated stations for them). Call before the first dump.
 * Returns the number of hour records written.
 */
int rl_wifi_recover(rl_wifi *w, rl_series *minute, rl_series *hour, int64_t now, rl_wifi_mac_fn mac_of, void *ctx);

/* ---- signal history ---- */

typedef enum { RL_SIGQ_LIVE, RL_SIGQ_MINUTE, RL_SIGQ_HOUR } rl_sigq_tier;

#define RL_SIGQ_DEFAULT_POINTS 500
#define RL_SIGQ_MAX_POINTS 1000
#define RL_SIGQ_MAX_RANGE (10LL * 366 * 86400)

typedef struct {
	rl_series *minute, *hour; /* may be NULL */
	const rl_wifi *wifi;      /* may be NULL */
	int64_t now;
	int minute_days, hour_days; /* retention */
	int live_step;              /* current station sampling interval (s) */
} rl_sigq_ctx;

typedef struct {
	int64_t ts;
	uint8_t flags; /* RL_SIG_F_*; 0 = no data */
	int8_t avg_signal, min_signal;
	uint32_t avg_tx_rate, avg_rx_rate;
	uint64_t tx_retries, tx_failed;
} rl_sig_point;

typedef struct {
	rl_sigq_tier tier;
	int64_t step;
	size_t n;
	rl_sig_point *pts;
} rl_sig_history;

/*
 * Signal curve of a device: the live ring when start is within the last RL_WIFI_LIVE_RANGE seconds and the
 * ring has points there (one point per sample), else minutes within their retention, else hours (a regular
 * grid with empty points where nothing was recorded). At most max_points points (0: default); buckets are
 * merged when the range has more. 0, or -1 for invalid arguments.
 */
int rl_sig_query(const rl_sigq_ctx *c, uint16_t dev, int64_t start, int64_t end, int max_points, rl_sig_history *out);
void rl_sig_history_free(rl_sig_history *h);
const char *rl_sigq_tier_name(rl_sigq_tier t);

/* ---- survey ---- */

enum { RL_SV_NOISE = 1, RL_SV_ACTIVE = 2, RL_SV_BUSY = 4, RL_SV_RX = 8, RL_SV_TX = 16 };

typedef struct {
	uint32_t wiphy;
	uint32_t freq;
	uint32_t has; /* RL_SV_* */
	bool in_use;
	int8_t noise;
	uint64_t active_ms, busy_ms, rx_ms, tx_ms;
} rl_survey_sample;

typedef struct {
	rl_survey_sample s;
	int busy_pct;       /* busy share between the last two samples; -1 = unknown (first sample, reset) */
	int busy_pct_total; /* busy share of all the time the counters cover (scan dwell times); -1 = unknown */
	int64_t updated;
	bool seen;
} rl_survey_entry;

/* One survey dump of a radio: begin, add per channel, end (drops channels of that radio not reported). */
void rl_wifi_survey_begin(rl_wifi *w, uint32_t wiphy);
const rl_survey_entry *rl_wifi_survey_add(rl_wifi *w, const rl_survey_sample *s, int64_t now);
void rl_wifi_survey_end(rl_wifi *w, uint32_t wiphy);
/* Drops radios that are not in the list (no AP interface any more). */
void rl_wifi_survey_retain(rl_wifi *w, const uint32_t *wiphys, size_t n);
size_t rl_wifi_survey_count(const rl_wifi *w);
const rl_survey_entry *rl_wifi_survey_at(const rl_wifi *w, size_t i);
/* The channel a radio works on: the entry at freq, else the one flagged in use; NULL when unknown. */
const rl_survey_entry *rl_wifi_survey_radio(const rl_wifi *w, uint32_t wiphy, uint32_t freq);

/* ---- helpers ---- */

/* IEEE channel number of a frequency in MHz (2.4/5/6/60 GHz), 0 when unknown. */
int rl_wifi_channel(uint32_t freq);
const char *rl_wifi_mode_name(rl_wifi_mode m);

#endif
