#include "t.h"

#include "core/version.h"

static void version_is_set(void)
{
	T_ASSERT(rl_version()[0] != '\0');
}

int main(void)
{
	T_RUN(version_is_set);
	T_DONE();
}
