/**
 * min2phaseCXX Copyright (C) 2022 Borgo Federico
 * This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
 * This is free software, and you are welcome to redistribute it
 * under certain conditions; type `show c' for details.
 *
 * This file contains a lot of useful function for the cube.
 * There is the random cube generator, the converter from a moves string to a cube,
 * the benchmarking, the tests, the verify that chek if a cube is solvable and a
 * super flip generator.
 */


#ifndef MIN2PHASE_TOOLS_H
#define MIN2PHASE_TOOLS_H 1

#include <cstdint>
#include <string>

/**
 * Useful functions for the cube.
 */
namespace min2phase { namespace tools {

    /**
     * This function is used to set a seed for randomize the cube.
     *
     * @param seed : the seed for the random number.
     */
    void setRandomSeed(uint32_t seed);

    /**
     * This is used to get a random cube state.
     *
     * @return : the string that contains the random cube.
     */
    std::string randomCube();

    /**
     * Generate a cube from a scramble.
     *
     * @param s : the scramble.
     * @return  : the scrambled cube.
     */
    std::string fromScramble(const std::string &s);

    /**
     * Generate a cube with the super flip: the cube where every edge is
     * twisted.
     *
     * @return  : the cube scrambled with every edge twisted.
     */
    std::string superFlip();

    /**
     * Print the result of the benchmark.
     */
    void benchmark();

    /**
     * Check if the cube is in a correct input.
     *
     * @return  : the value of the error.
     */
    int8_t verify(const std::string& facelets);

    /**
     * Tests the algorithm.
     */
    void testAlgorithm();

}   }

#endif //MIN2PHASE_TOOLS_H