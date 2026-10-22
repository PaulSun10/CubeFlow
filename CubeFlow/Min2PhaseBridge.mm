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
#include <chrono>

namespace {
#if DEBUG
thread_local double lastSearchTiming[3] = {};
double millisecondsSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
}
#endif
bool cubieCubeFromFacelets(const std::string &facelets, min2phase::CubieCube &cube) {
    if (facelets.length() != min2phase::info::N_PLATES) {
        return false;
    }

    const int centerIndices[] = {
        min2phase::info::U5, min2phase::info::R5, min2phase::info::F5,
        min2phase::info::D5, min2phase::info::L5, min2phase::info::B5
    };
    char centers[min2phase::info::FACES];
    int8_t colors[min2phase::info::N_PLATES];
    int counts[min2phase::info::FACES] = {};
    for (int face = 0; face < min2phase::info::FACES; face++) {
        centers[face] = facelets[centerIndices[face]];
    }
    for (int index = 0; index < min2phase::info::N_PLATES; index++) {
        colors[index] = -1;
        for (int face = 0; face < min2phase::info::FACES; face++) {
            if (facelets[index] == centers[face]) {
                colors[index] = static_cast<int8_t>(face);
                counts[face]++;
                break;
            }
        }
        if (colors[index] < 0) {
            return false;
        }
    }
    for (int count : counts) {
        if (count != min2phase::info::N_PLATES_X_FACE) {
            return false;
        }
    }
    min2phase::CubieCube::toCubieCube(colors, cube);
    return cube.check() == min2phase::info::NO_ERROR;
}

NSString *validatedSolution(const std::string &solution) {
    if (solution.empty()) {
        return @"";
    }
    for (char character : solution) {
        if (character < '0' || character > '9') {
            return [NSString stringWithUTF8String:solution.c_str()];
        }
    }
    return @"";
}
}

@implementation Min2PhaseBridge
#if DEBUG
+ (NSArray<NSNumber *> *)debugSearchTiming {
    return @[@(lastSearchTiming[0]), @(lastSearchTiming[1]), @(lastSearchTiming[2])];
}
#endif

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

    return validatedSolution(solution);
}

+ (NSString *)movesFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets {
    return [self searchFromFacelets:sourceFacelets toFacelets:targetFacelets maximumDepth:21
                        probeLimit:1000000 minimumProbes:0 optimal:NO];
}

+ (NSString *)searchFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets
                   maximumDepth:(NSInteger)maximumDepth probeLimit:(NSInteger)probeLimit
                  minimumProbes:(NSInteger)minimumProbes optimal:(BOOL)optimal {
    return [self searchFromFacelets:sourceFacelets toFacelets:targetFacelets maximumDepth:maximumDepth
                        probeLimit:probeLimit minimumProbes:minimumProbes optimal:optimal
               maximumMilliseconds:0 cancelled:nil];
}

+ (NSString *)searchFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets
                   maximumDepth:(NSInteger)maximumDepth probeLimit:(NSInteger)probeLimit
                  minimumProbes:(NSInteger)minimumProbes optimal:(BOOL)optimal
            maximumMilliseconds:(NSInteger)maximumMilliseconds cancelled:(BOOL (NS_NOESCAPE ^)(void))cancelled {
    if (cancelled && cancelled()) { return @""; }
    #if DEBUG
    lastSearchTiming[0] = lastSearchTiming[1] = lastSearchTiming[2] = 0;
    const auto tablesStart = std::chrono::steady_clock::now();
    #endif
    [self initializeTables];
    #if DEBUG
    lastSearchTiming[0] = millisecondsSince(tablesStart);
    const auto normalizationStart = std::chrono::steady_clock::now();
    #endif
    min2phase::CubieCube source;
    min2phase::CubieCube target;
    if (!cubieCubeFromFacelets([sourceFacelets UTF8String], source)
        || !cubieCubeFromFacelets([targetFacelets UTF8String], target)) {
        return @"";
    }

    source.inv();
    min2phase::CubieCube relative;
    min2phase::CubieCube::cornMult(source, target, relative);
    min2phase::CubieCube::edgeMult(source, target, relative);
    #if DEBUG
    lastSearchTiming[1] = millisecondsSince(normalizationStart);
    const auto searchStart = std::chrono::steady_clock::now();
    #endif

    const int32_t boundedProbes = static_cast<int32_t>(MAX(1, MIN(probeLimit, 1000000)));
    min2phase::Search search;
    if (maximumMilliseconds > 0 || cancelled) {
        const auto deadline = std::chrono::steady_clock::now()
            + std::chrono::milliseconds(MAX(0, maximumMilliseconds));
        search.setInterruption([deadline, maximumMilliseconds, cancelled] {
            return (cancelled && cancelled()) || (maximumMilliseconds > 0
                && std::chrono::steady_clock::now() >= deadline);
        });
    }
    std::string solution = search.solve(
        min2phase::CubieCube::toFaceCube(relative),
        static_cast<int8_t>(MAX(0, MIN(maximumDepth, 21))),
        boundedProbes,
        static_cast<int32_t>(MAX(0, MIN(minimumProbes, boundedProbes))),
        min2phase::INVERSE_SOLUTION | (optimal ? min2phase::OPTIMAL_SOLUTION : 0),
        nullptr
    );
    #if DEBUG
    lastSearchTiming[2] = millisecondsSince(searchStart);
    #endif
    return validatedSolution(solution);
}

@end
