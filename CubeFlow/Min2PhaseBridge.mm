#import "Min2PhaseBridge.h"

#include <min2phase/min2phase.h>
#include <min2phase/tools.h>

#include "Search.h"
#include "coords.h"
#include "info.h"
#include "CubieCube.h"

#include <mutex>
#include <cstdlib>
#include <random>

@implementation Min2PhaseBridge

+ (void)initializeTables {
    static std::once_flag onceToken;
    std::call_once(onceToken, [] {
        min2phase::info::init();
        min2phase::coords::init();
        min2phase::tools::setRandomSeed((uint32_t)arc4random());
    });
}

+ (NSString *)randomStateFacelets {
    [self initializeTables];
    static thread_local std::mt19937_64 rng([] {
        uint64_t seed = (static_cast<uint64_t>(arc4random()) << 32) | arc4random();
        return std::mt19937_64(seed);
    }());

    std::uniform_int_distribution<int32_t> cornerPermDist(0, min2phase::info::N_PERM - 1);
    std::uniform_int_distribution<int16_t> cornerOriDist(0, min2phase::info::N_TWIST - 1);
    std::uniform_int_distribution<int16_t> edgeOriDist(0, min2phase::info::N_FLIP - 1);
    std::uniform_int_distribution<int32_t> edgePermDist(0, min2phase::info::FULL_E_PERM - 1);

    min2phase::CubieCube cube;

    int8_t parity = 0;
    int16_t cornerOri = 0;
    int16_t edgeOri = 0;
    uint16_t cornerPerm = 0;
    int32_t edgePerm = 0;

    cornerPerm = static_cast<uint16_t>(cornerPermDist(rng));
    cornerOri = cornerOriDist(rng);
    edgeOri = edgeOriDist(rng);
    parity = min2phase::CubieCube::getNParity(cornerPerm, min2phase::info::NUMBER_CORNER);

    do {
        edgePerm = edgePermDist(rng);
    } while (min2phase::CubieCube::getNParity(edgePerm, min2phase::info::NUMBER_EDGES) != parity);

    cube.setCoords(cornerPerm, cornerOri, edgePerm, edgeOri);
    std::string facelets = min2phase::CubieCube::toFaceCube(cube);
    return [NSString stringWithUTF8String:facelets.c_str()];
}

+ (NSString *)solveFacelets:(NSString *)facelets {
    [self initializeTables];
    std::string faceletsStr = [facelets UTF8String];
    min2phase::Search search;
    std::string solution = search.solve(faceletsStr, 21, 1000000, 0, 0, nullptr);

    if (solution.empty()) {
        return @"";
    }

    bool allDigits = true;
    for (char c : solution) {
        if (c < '0' || c > '9') {
            allDigits = false;
            break;
        }
    }
    if (allDigits) {
        return @"";
    }

    return [NSString stringWithUTF8String:solution.c_str()];
}

@end
