#include "info.h"
#include "coords.h"
#include "Search.h"
#include "tools.h"

#include <ctime>
#include <mutex>

namespace {
    std::once_flag gMin2PhaseInitFlag;
}

namespace min2phase {
    void init() {
        std::call_once(gMin2PhaseInitFlag, [] {
            info::init();
            coords::init();
            tools::setRandomSeed(static_cast<uint32_t>(time(nullptr)));
        });
    }

    std::string solve(const std::string& facelets, int8_t maxDepth, int32_t probeMax, int32_t probeMin, int8_t verbose,
                      uint8_t* usedMoves) {
        init();
        Search search;
        return search.solve(facelets, maxDepth, probeMax, probeMin, verbose, usedMoves);
    }
}
