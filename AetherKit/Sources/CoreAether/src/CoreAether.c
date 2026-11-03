#include <CoreAether/aether.h>
#include <CoreAether/mach-o.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

static_assert(sizeof(struct n_type_field) == 1, "n_type_field must be one byte wide");
static_assert(((N_SECT >> 1) & 0x7) == 7, "N_SECT does not fit in n_type:3");
static_assert(sizeof(struct nlist_64) == 16, "the decoded n_type field must not shift n_sect/n_desc/n_value");
