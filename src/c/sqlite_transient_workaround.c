#include "sqlite_transient_workaround.h"

// Use in place of `SQLITE_TRANSIENT` #DEFINE to get around compilation errors.
my_sqlite3_destructor_type sqliteTransientAsDestructor() {
  return (my_sqlite3_destructor_type)-1;
}
