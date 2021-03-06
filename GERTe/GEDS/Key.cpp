#include "Key.h"
#include "Address.h"
#include <map>

std::map<Address, Key> resolutions;

extern "C" {
	void addResolution(Address addr, Key key) {
		resolutions[addr] = key;
	}

	void removeResolution(Address addr) {
		resolutions.erase(addr);
	}
}
