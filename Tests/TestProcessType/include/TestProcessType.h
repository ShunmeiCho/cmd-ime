#ifndef TEST_PROCESS_TYPE_H
#define TEST_PROCESS_TYPE_H

/// Does nothing. The test bundle refers to it so that the linker keeps this module, whose
/// load-time constructor is the point (see TestProcessType.c).
void test_process_type_anchor(void);

#endif
