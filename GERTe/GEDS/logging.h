#ifndef __LOGGING__
#define __LOGGING__
#include <string>
using namespace std;

void log(string);
void warn(string);
void error(string);
void debug(string);
void startLog();
void stopLog();
#endif
