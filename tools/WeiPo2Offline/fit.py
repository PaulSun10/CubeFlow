#!/usr/bin/env python3
"""Offline WeiPo V5 AI 2x2 geometry and capture fitter. No app imports.

Run: python3 Tools/WeiPo2Offline/fit.py
The default captures are read from ~/Downloads/{A,C,F,G,H}.txt.
"""

from __future__ import annotations

from collections import Counter
from itertools import permutations, product
from math import acos, degrees, prod, sqrt
from pathlib import Path
import re
import struct


Vec = tuple[int, int, int]
Matrix = tuple[Vec, Vec, Vec]  # Row-major.
FACES = "URFDLB"
NORMAL: dict[str, Vec] = {
    "U": (0, 1, 0), "R": (1, 0, 0), "F": (0, 0, 1),
    "D": (0, -1, 0), "L": (-1, 0, 0), "B": (0, 0, -1),
}
RIGHT_UP: dict[str, tuple[Vec, Vec]] = {
    "U": ((1, 0, 0), (0, 0, -1)),
    "R": ((0, 0, -1), (0, 1, 0)),
    "F": ((1, 0, 0), (0, 1, 0)),
    "D": ((1, 0, 0), (0, 0, 1)),
    "L": ((0, 0, 1), (0, 1, 0)),
    "B": ((-1, 0, 0), (0, 1, 0)),
}
BY_NORMAL = {value: key for key, value in NORMAL.items()}
S0_HEX = "00 02 49 49 26 DB 92 4B 6D"
S1_HEX = "00 02 49 4A 4B 5B 8E 35 55"
S2_HEX = "00 02 49 49 B4 9B 96 59 65"
S4_HEX = "0C 34 51 41 06 59 92 4B 6D"  # Existing protocol-boundary fixture.
A_PRE_HEX = "90 0B 49 49 26 DB 26 40 2D"  # A prelude, before code 2 restores S0.
HEX_PACKET = re.compile(
    r"^(pre\+|\+)([0-9.]+) decoded \S+ ((?:[0-9A-F]{2} ){19}[0-9A-F]{2})$"
)


def add(a: Vec, b: Vec) -> Vec:
    return tuple(x + y for x, y in zip(a, b))  # type: ignore[return-value]


def scale(k: int, a: Vec) -> Vec:
    return tuple(k * x for x in a)  # type: ignore[return-value]


def dot(a: Vec, b: Vec) -> int:
    return sum(x * y for x, y in zip(a, b))


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def apply(matrix: Matrix, vector: Vec) -> Vec:
    return tuple(dot(row, vector) for row in matrix)  # type: ignore[return-value]


def determinant(matrix: Matrix) -> int:
    return dot(matrix[0], cross(matrix[1], matrix[2]))


def quarter(axis: Vec, sense: int) -> Matrix:
    # Rodrigues at +/-90 degrees, exact integer arithmetic.
    basis: tuple[Vec, Vec, Vec] = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    columns = [add(scale(dot(axis, e), axis), scale(sense, cross(axis, e))) for e in basis]
    return tuple(tuple(columns[col][row] for col in range(3)) for row in range(3))  # type: ignore[return-value]


def matrix_angle(matrix: Matrix) -> int:
    trace = sum(matrix[i][i] for i in range(3))
    return round(degrees(acos(max(-1.0, min(1.0, (trace - 1) / 2)))))


def multiply(a: Matrix, b: Matrix) -> Matrix:
    columns = tuple(tuple(b[row][col] for row in range(3)) for col in range(3))
    return tuple(tuple(dot(row, column) for column in columns) for row in a)  # type: ignore[return-value]


def inverse(matrix: Matrix) -> Matrix:
    return tuple(tuple(matrix[col][row] for col in range(3)) for row in range(3))  # type: ignore[return-value]


ROTATIONS: tuple[Matrix, ...] = tuple(
    matrix for perm in permutations(range(3)) for signs in product((-1, 1), repeat=3)
    if determinant(matrix := tuple(
        tuple(signs[row] if col == perm[row] else 0 for col in range(3))
        for row in range(3)
    )) == 1
)
IDENTITY: Matrix = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def facelets() -> tuple[tuple[Vec, Vec], ...]:
    result = []
    for face in FACES:
        normal = NORMAL[face]
        right, up = RIGHT_UP[face]
        for row, col in product(range(2), repeat=2):
            position = add(normal, add(scale(1 - 2 * row, up), scale(2 * col - 1, right)))
            result.append((position, normal))
    return tuple(result)


STICKERS = facelets()
STICKER_INDEX = {key: index for index, key in enumerate(STICKERS)}
SOLVED = tuple(face for face in FACES for _ in range(4))


def permute_state(state: tuple, matrix: Matrix, layer: str | None = None) -> tuple:
    result = list(state)
    layer_normal = NORMAL[layer] if layer else None
    for index, (position, normal) in enumerate(STICKERS):
        if layer_normal is not None and dot(position, layer_normal) != 1:
            continue
        target = STICKER_INDEX[(apply(matrix, position), apply(matrix, normal))]
        result[target] = state[index]
    return tuple(result)


def turn(state: tuple, face: str, direction: int = 1) -> tuple:
    # direction=+1 is standard clockwise as viewed from outside the face.
    return permute_state(state, quarter(NORMAL[face], -direction), face)


def gauge_state(state: tuple[str, ...], matrix: Matrix) -> tuple[str, ...]:
    # Rotate both sticker positions and the face-color names; solved stays solved.
    transformed = permute_state(state, matrix)
    return tuple(BY_NORMAL[apply(matrix, NORMAL[color])] for color in transformed)


def decode_a3(hex_bytes: str) -> tuple[int, ...]:
    word = int.from_bytes(bytes.fromhex(hex_bytes), "big")
    return tuple((word >> (72 - 3 * (index + 1))) & 7 for index in range(24))


S0, S1, S2 = (decode_a3(value) for value in (S0_HEX, S1_HEX, S2_HEX))
S4 = decode_a3(S4_HEX)
A_PRE = decode_a3(A_PRE_HEX)
NATIVE_STATES = {S0: "S0", S1: "S1", S2: "S2", S4: "S4"}


def d4_permutations() -> tuple[tuple[int, ...], ...]:
    result = set()
    for reflection in (False, True):
        for turns in range(4):
            permutation = []
            for row, col in product(range(2), repeat=2):
                if reflection:
                    col = 1 - col
                for _ in range(turns):
                    row, col = col, 1 - row
                permutation.append(2 * row + col)
            result.add(tuple(permutation))
    return tuple(sorted(result))


D4 = d4_permutations()


def fit_native_topology() -> list[tuple[tuple[str, ...], str, int, str, int, tuple[int, ...]]]:
    # A native group is one geometric face with an unknown D4-local index order.
    # The color name on that face is its native group number, not a physical color.
    fits = []
    for assignment in permutations(FACES):
        if NORMAL[assignment[0]] != scale(-1, NORMAL[assignment[1]]):
            continue
        initial = tuple(assignment.index(face) for face in FACES for _ in range(4))
        for moved_face in assignment[:2]:
            for direction in (-1, 1):
                once = turn(initial, moved_face, direction)
                twice = turn(once, moved_face, direction)
                for other_face in assignment[4:6]:
                    for other_direction in (-1, 1):
                        other = turn(initial, other_face, other_direction)
                        choices = []
                        for group, face in enumerate(assignment):
                            base = FACES.index(face) * 4
                            options = [p for p in D4 if all(
                                S1[group * 4 + i] == once[base + p[i]]
                                and S2[group * 4 + i] == twice[base + p[i]]
                                and S4[group * 4 + i] == other[base + p[i]]
                                for i in range(4)
                            )]
                            if not options:
                                break
                            choices.append(len(options))
                        if len(choices) == 6:
                            fits.append((assignment, moved_face, direction,
                                         other_face, other_direction, tuple(choices)))
    return fits


def predicted_axis_payloads(
    fits: list[tuple[tuple[str, ...], str, int, str, int, tuple[int, ...]]],
    face: str,
    direction: int = 1,
) -> set[str]:
    """Exact native axis A3 predictions from surviving topology fits."""
    result = set()
    for assignment, moved_face, direction, other_face, other_direction, _ in fits:
        initial = tuple(assignment.index(face) for face in FACES for _ in range(4))
        once = turn(initial, moved_face, direction)
        twice = turn(once, moved_face, direction)
        other = turn(initial, other_face, other_direction)
        target_state = turn(initial, face, direction)
        options_by_group = []
        for group, face in enumerate(assignment):
            base = FACES.index(face) * 4
            options_by_group.append([p for p in D4 if all(
                S1[group * 4 + i] == once[base + p[i]]
                and S2[group * 4 + i] == twice[base + p[i]]
                and S4[group * 4 + i] == other[base + p[i]]
                for i in range(4)
            )])
        for orientations in product(*options_by_group):
            values = [target_state[FACES.index(assignment[group]) * 4 + orientations[group][i]]
                      for group in range(6) for i in range(4)]
            word = 0
            for value in values:
                word = (word << 3) | value
            result.add(word.to_bytes(9, "big").hex().upper())
    return result


DEFAULT_BASIS = ("F", "U", "R")  # Native preferred faces for codes 0, 2, 4.


def preferred_for(face: str, basis: tuple[str, str, str]) -> str:
    return next(candidate for candidate in basis
                if abs(dot(NORMAL[face], NORMAL[candidate])) == 1)


def physical_step(native: tuple, frame: Matrix, face: str, direction: int,
                  basis: tuple[str, str, str] = DEFAULT_BASIS) -> tuple[tuple, Matrix, int]:
    """Exact layer-turn factorization for any 2x2 sticker state.

    ``frame`` maps native sticker coordinates into the physical/body frame.
    A turn of a non-preferred native face is the preferred-face turn followed
    by a whole-cube quarter rotation. This is an algebraic identity, not an
    AB-based classifier.
    """
    native_face = BY_NORMAL[apply(inverse(frame), NORMAL[face])]
    preferred = preferred_for(native_face, basis)
    code = 2 * basis.index(preferred) + (direction == -1)
    changed = turn(native, preferred, direction)
    if native_face == preferred:
        return changed, frame, code
    whole_rotation = quarter(NORMAL[native_face], -direction)
    return changed, multiply(frame, whole_rotation), code


def simulate(actions: tuple[str, ...], initial_frame: Matrix,
             basis: tuple[str, str, str] = DEFAULT_BASIS) -> tuple[list[int], list[str]]:
    native = permute_state(SOLVED, inverse(initial_frame))
    frame = initial_frame
    physical = SOLVED
    codes, reference_changes = [], []
    for action in actions:
        face = action[0]
        direction = -1 if action.endswith("'") else 1
        physical = turn(physical, face, direction)
        changed, new_frame, code = physical_step(native, frame, face, direction, basis)
        assert permute_state(changed, new_frame) == physical, (
            "factorization failed", action, code
        )
        codes.append(code)
        if new_frame != frame:
            reference_changes.append(action)
        native, frame = changed, new_frame
    return codes, reference_changes


def predict_events(actions: tuple[str, ...], initial_frame: Matrix,
                   basis: tuple[str, str, str]) -> tuple[list[int], list[str]]:
    frame = initial_frame
    codes, changes = [], []
    for action in actions:
        native_face = BY_NORMAL[apply(inverse(frame), NORMAL[action[0]])]
        preferred = preferred_for(native_face, basis)
        direction = -1 if action.endswith("'") else 1
        codes.append(2 * basis.index(preferred) + (direction == -1))
        if native_face != preferred:
            frame = multiply(frame, quarter(NORMAL[native_face], -direction))
            changes.append(action)
    return codes, changes


def initial_native(assignment: tuple[str, ...]) -> tuple[int, ...]:
    return tuple(assignment.index(face) for face in FACES for _ in range(4))


def encode_native(state: tuple[int, ...], assignment: tuple[str, ...],
                  orders: tuple[tuple[int, ...], ...]) -> str:
    word = 0
    for group, face in enumerate(assignment):
        base = FACES.index(face) * 4
        for offset in orders[group]:
            word = (word << 3) | state[base + offset]
    return word.to_bytes(9, "big").hex().upper()


def report_exact_a3_fit(
    models: list[tuple[tuple[str, str, str], tuple[str, ...],
                       tuple[tuple[int, ...], ...], Matrix, Matrix]]
) -> None:
    unique_u, unique_after_bu = set(), set()
    for basis, assignment, orders, current_frame, older_frame in models:
        initial = initial_native(assignment)
        assert encode_native(initial, assignment, orders) == bytes.fromhex(S0_HEX).hex().upper()
        assert encode_native(turn(initial, basis[1], -1), assignment, orders) == \
            bytes.fromhex(A_PRE_HEX).hex().upper()
        unique_u.add(encode_native(turn(initial, basis[1], 1), assignment, orders))

        native, frame = initial, current_frame
        expected = (S1, S0, S1, S2, S1, S0, S1, S0)
        for action, target in zip(("F", "F'", "B", "F", "F'", "B'", "F", "F'"), expected):
            native, frame, _ = physical_step(native, frame, action[0],
                                             -1 if action.endswith("'") else 1, basis)
            assert decode_a3(encode_native(native, assignment, orders)) == target

        native, frame = initial, current_frame
        stateful = []
        for action in ("B'", "U", "U'", "B"):
            native, frame, _ = physical_step(native, frame, action[0],
                                             -1 if action.endswith("'") else 1, basis)
            stateful.append(encode_native(native, assignment, orders))
        assert stateful[0] == stateful[2] and stateful[3] == bytes.fromhex(S0_HEX).hex().upper()
        unique_after_bu.add(stateful[1])

        native, frame, code = physical_step(initial, older_frame, "F", 1, basis)
        assert code == 4
        assert encode_native(native, assignment, orders) == bytes.fromhex(S4_HEX).hex().upper()
    print("  exact A3 replay: all surviving models reproduce S0/S1/S2, "
          "the earlier code-4 S4, and A's prelude predecessor")
    print("  native U-from-S0 payload variants:", len(unique_u), sorted(unique_u))
    print("  B' then U intermediate payload variants (raw earlier A3 unavailable):",
          len(unique_after_bu), sorted(unique_after_bu))


def search_complete_models(
    fits: list[tuple[tuple[str, ...], str, int, str, int, tuple[int, ...]]]
) -> list[tuple[tuple[str, str, str], tuple[str, ...],
                tuple[tuple[int, ...], ...], Matrix, Matrix]]:
    """Intersect A3 layout, A prelude, stateful-U, and six-face constraints."""
    stateful = ("B'", "U", "U'", "B")
    six_face = tuple(move for face in "FURBDL" for move in (face, face + "'"))
    surviving = []
    for assignment, code0_face, dir0, code4_face, dir4, _ in fits:
        if dir0 != 1 or dir4 != 1:
            continue
        initial = tuple(assignment.index(face) for face in FACES for _ in range(4))
        once = turn(initial, code0_face, 1)
        twice = turn(once, code0_face, 1)
        other = turn(initial, code4_face, 1)
        for code2_face in assignment[2:4]:
            basis = (code0_face, code2_face, code4_face)
            if any(abs(dot(NORMAL[a], NORMAL[b])) for a, b in
                   ((basis[0], basis[1]), (basis[0], basis[2]), (basis[1], basis[2]))):
                continue
            predecessor = turn(initial, code2_face, -1)
            options_by_group = []
            for group, face in enumerate(assignment):
                base = FACES.index(face) * 4
                options = [p for p in D4 if all(
                    S1[group * 4 + i] == once[base + p[i]]
                    and S2[group * 4 + i] == twice[base + p[i]]
                    and S4[group * 4 + i] == other[base + p[i]]
                    and A_PRE[group * 4 + i] == predecessor[base + p[i]]
                    for i in range(4)
                )]
                if not options:
                    break
                options_by_group.append(options)
            if len(options_by_group) != 6:
                continue
            current_frames = [r for r in ROTATIONS
                              if apply(r, NORMAL[code0_face]) == NORMAL["F"]
                              and predict_events(stateful, r, basis) ==
                              ([1, 4, 5, 0], ["B'", "U", "U'", "B"])]
            earlier_frames = [r for r in ROTATIONS
                              if predict_events(six_face, r, basis) ==
                              ([4, 5, 2, 3, 0, 1, 4, 5, 2, 3, 0, 1],
                               ["R", "R'", "B", "B'", "D", "D'"])]
            if current_frames and earlier_frames:
                for orders in product(*options_by_group):
                    for current in current_frames:
                        for earlier in earlier_frames:
                            surviving.append((basis, assignment, orders,
                                              current, earlier))
    return surviving


def qnorm(q: tuple[float, ...]) -> tuple[float, ...]:
    length = sqrt(sum(value * value for value in q))
    return tuple(value / length for value in q)


def qmul(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    w, x, y, z = a
    v, i, j, k = b
    return (w * v - x * i - y * j - z * k,
            w * i + x * v + y * k - z * j,
            w * j - x * k + y * v + z * i,
            w * k + x * j - y * i + z * v)


def qinv(q: tuple[float, ...]) -> tuple[float, ...]:
    return (q[0], -q[1], -q[2], -q[3])


def qaxis(q: tuple[float, ...]) -> tuple[float, tuple[float, float, float]]:
    q = qnorm(q)
    if q[0] < 0:
        q = tuple(-value for value in q)
    angle = degrees(2 * acos(max(-1.0, min(1.0, q[0]))))
    length = sqrt(sum(value * value for value in q[1:]))
    axis = tuple(value / length for value in q[1:]) if length else (0.0, 0.0, 0.0)
    return angle, axis  # type: ignore[return-value]


def quaternion_from_matrix(matrix: Matrix) -> tuple[float, ...]:
    # Trace-free diagonal cases are handled by choosing the largest component.
    w2 = max(0.0, (1 + matrix[0][0] + matrix[1][1] + matrix[2][2]) / 4)
    x2 = max(0.0, (1 + matrix[0][0] - matrix[1][1] - matrix[2][2]) / 4)
    y2 = max(0.0, (1 - matrix[0][0] + matrix[1][1] - matrix[2][2]) / 4)
    z2 = max(0.0, (1 - matrix[0][0] - matrix[1][1] + matrix[2][2]) / 4)
    values = [sqrt(w2), sqrt(x2), sqrt(y2), sqrt(z2)]
    largest = max(range(4), key=lambda i: values[i])
    w, x, y, z = values
    if largest == 0:
        x = (matrix[2][1] - matrix[1][2]) / (4 * w)
        y = (matrix[0][2] - matrix[2][0]) / (4 * w)
        z = (matrix[1][0] - matrix[0][1]) / (4 * w)
    elif largest == 1:
        w = (matrix[2][1] - matrix[1][2]) / (4 * x)
        y = (matrix[0][1] + matrix[1][0]) / (4 * x)
        z = (matrix[0][2] + matrix[2][0]) / (4 * x)
    elif largest == 2:
        w = (matrix[0][2] - matrix[2][0]) / (4 * y)
        x = (matrix[0][1] + matrix[1][0]) / (4 * y)
        z = (matrix[1][2] + matrix[2][1]) / (4 * y)
    else:
        w = (matrix[1][0] - matrix[0][1]) / (4 * z)
        x = (matrix[0][2] + matrix[2][0]) / (4 * z)
        y = (matrix[1][2] + matrix[2][1]) / (4 * z)
    return qnorm((w, x, y, z))


def quaternion_error(a: tuple[float, ...], b: tuple[float, ...]) -> float:
    return degrees(2 * acos(max(-1.0, min(1.0, abs(sum(x * y for x, y in zip(a, b)))))))


def median_quaternion(values: list[tuple[float, ...]]) -> tuple[float, ...]:
    from statistics import median

    first = values[0]
    aligned = [q if sum(x * y for x, y in zip(q, first)) >= 0 else tuple(-x for x in q)
               for q in values]
    return qnorm(tuple(median(q[i] for q in aligned) for i in range(4)))


def packets(path: Path) -> dict[str, list[tuple[float, bytes]]]:
    parts: dict[str, list[tuple[float, bytes]]] = {"pre+": [], "+": []}
    for line in path.read_text().splitlines():
        match = HEX_PACKET.match(line)
        if match:
            parts[match[1]].append((float(match[2]), bytes.fromhex(match[3])))
    return parts


def report_captures() -> None:
    labels = {
        "A": ("F", "F'"), "C": ("F", "F'"),
        "F": ("F", "F'", "B", "F", "F'", "B'", "F", "F'"),
        "G": ("B", "F", "F'"), "H": ("F", "F'", "B'"),
    }
    for name, actions in labels.items():
        path = Path.home() / "Downloads" / f"{name}.txt"
        if not path.exists():
            print(f"capture {name}: MISSING; skipping")
            continue
        parts = packets(path)
        main = parts["+"]
        before = parts["pre+"]
        if name == "A":
            pre_a3 = [(t, packet) for t, packet in before if packet[0] == 0xA3]
            pre_a5 = [(t, packet) for t, packet in before if packet[0] == 0xA5]
            assert len(pre_a5) == 1 and pre_a5[0][1][13] == 0x8A
            assert pre_a5[0][1][14] >> 5 == 2
            assert any(t < pre_a5[0][0] and packet[10] == 0x89
                       and packet[1:10] == bytes.fromhex(A_PRE_HEX)
                       for t, packet in pre_a3)
            assert any(t > pre_a5[0][0] and packet[10] == 0x8A
                       and packet[1:10] == bytes.fromhex(S0_HEX)
                       for t, packet in pre_a3)
        a3 = [(t, bytes(packet[1:10]), packet[10]) for t, packet in main if packet[0] == 0xA3]
        a5 = [(t, packet) for t, packet in main if packet[0] == 0xA5]
        ab = []
        for t, packet in main:
            if packet[0] == 0xAB:
                w, x, minus_z, y = struct.unpack("<4i", packet[1:17])
                ab.append((t, qnorm(tuple(value / (2**30) for value in (w, x, y, -minus_z)))))
        unique_states = Counter(packet[1:10].hex().upper() for _, packet in before + main if packet[0] == 0xA3)
        print(f"capture {name}: {len(a5)} main A5, {len(ab)} main AB, "
              f"{len(unique_states)} distinct A3 payload(s)")
        assert len(a5) == len(actions), (name, len(a5), len(actions))
        for index, (t, packet) in enumerate(a5):
            state_before = next((value for ts, value, _ in reversed(a3) if ts < t), None)
            state_after = next((value for ts, value, counter in a3
                                if ts > t and counter == packet[13]), None)
            assert state_after is not None, (name, packet[13])
            code = packet[14] >> 5
            before_name = NATIVE_STATES.get(decode_a3(state_before.hex()), "other") if state_before else "?"
            after_name = NATIVE_STATES.get(decode_a3(state_after.hex()), "other")
            pre = [q for ts, q in ab if t - .65 <= ts <= t - .25]
            post = [q for ts, q in ab if t + .55 <= ts <= t + .95]
            if pre and post:
                q_before = median_quaternion(pre)
                q_after = median_quaternion(post)
                q_delta = qmul(qinv(q_before), q_after)
                alternate_order = qmul(q_after, qinv(q_before))
                angle, axis = qaxis(q_delta)
                nearest = min(ROTATIONS, key=lambda rotation: quaternion_error(
                    q_delta, quaternion_from_matrix(rotation)))
                error = quaternion_error(q_delta, quaternion_from_matrix(nearest))
                ab_text = (f"AB {angle:5.1f}deg axis "
                           f"({axis[0]:+.2f},{axis[1]:+.2f},{axis[2]:+.2f}), "
                           f"nearest cube {matrix_angle(nearest)}deg err {error:.1f}deg")
                direction = -1 if actions[index].endswith("'") else 1
                expected = (quarter(NORMAL["B"], -direction)
                            if actions[index][0] == "B" else IDENTITY)
                alternative = (IDENTITY if actions[index][0] == "B"
                               else quarter(NORMAL["B"], -direction))
                match = quaternion_error(q_delta, quaternion_from_matrix(expected))
                other = quaternion_error(q_delta, quaternion_from_matrix(alternative))
                ab_text += f"; model {match:.1f}deg vs other side {other:.1f}deg"
                if actions[index][0] == "B":
                    alternate = quaternion_error(alternate_order,
                                                 quaternion_from_matrix(expected))
                    ab_text += f"; opposite multiplication {alternate:.1f}deg"
            else:
                ab_text = "AB window missing"
            print(f"  {actions[index]:>2} #{packet[13]:02X} code {code} "
                  f"{before_name}->{after_name}; {ab_text}")
        print("  A3 payloads:", ", ".join(f"{key} x{count}" for key, count in sorted(unique_states.items())))


def report_geometry() -> None:
    fits = fit_native_topology()
    print(f"proper rotations: {len(ROTATIONS)}, angles: "
          f"{dict(sorted(Counter(matrix_angle(r) for r in ROTATIONS).items()))}")
    print(f"native D4 topology fits to S0->S1->S2 and S0->S4: "
          f"{len(fits)} assignments/turn choices")
    if fits:
        constrained = [fit for fit in fits if set(fit[0][:2]) == {"F", "B"}]
        print(f"  with native axis 0 physically F/B: {len(constrained)}")
        f_forward = [fit for fit in constrained if fit[1:3] == ("F", 1)]
        print(f"  with physical F -> native F clockwise: {len(f_forward)}")
        strict = [fit for fit in fits if fit[1:3] == ("F", 1)
                  and fit[3:5] == ("R", 1)]
        print(f"  with native preferred F(code 0) and R(code 4): {len(strict)}; "
              f"assignments {[fit[0] for fit in strict]}")
        print(f"  possible unobserved native U A3 payloads: "
              f"{len(predicted_axis_payloads(strict, 'U'))}")
        for face in ("U", "D"):
            for direction in (-1, 1):
                candidates = predicted_axis_payloads(strict, face, direction)
                print(f"  A prelude state fits {face} direction {direction:+}:",
                      bytes.fromhex(A_PRE_HEX).hex().upper() in candidates,
                      f"among {len(candidates)} candidates")
        print("  first fit (groups -> faces, code0 turn, code4 turn, local D4 counts):", fits[0])
        print("  per-fit sticker-order possibilities: min", min(prod(f[5]) for f in fits),
              "max", max(prod(f[5]) for f in fits))
        survivors = search_complete_models(fits)
        print("  complete-model survivors including A prelude, stateful U, six-face:",
              len(survivors), "unique bases", len(set(model[0] for model in survivors)))
        code0_f = [model for model in survivors if model[0][0] == "F"]
        print("  code-0-native-F representatives (basis, groups->faces, current/older frame angle):")
        for basis, assignment, _, current_frame, older_frame in code0_f[:8]:
            print("   ", basis, assignment, matrix_angle(current_frame),
                  matrix_angle(older_frame))
        assert len(survivors) == 48
        assert len(set(model[0] for model in survivors)) == 24
        assert all(sum(1 for model in survivors if model[0] == basis) == 2
                   for basis in set(model[0] for model in survivors))
        report_exact_a3_fit(survivors)
    for first, opposite in (("F", "B"), ("U", "D"), ("R", "L")):
        one = turn(SOLVED, first)
        other = turn(SOLVED, opposite)
        pose = [rotation for rotation in ROTATIONS if permute_state(one, rotation) == other]
        gauge = [rotation for rotation in ROTATIONS if gauge_state(one, rotation) == other]
        print(f"{first}/{opposite}: same colored state by pose-only rotation: "
              f"{len(pose)} angles {[matrix_angle(r) for r in pose]}; by spatial+color-frame rotation: "
              f"{len(gauge)} angles {[matrix_angle(r) for r in gauge]}")
    b_reference = quarter(NORMAL["B"], -1)
    assert permute_state(turn(SOLVED, "F"), b_reference) == turn(SOLVED, "B")
    print("observationally equivalent endpoints: F + rigid B-axis quarter "
          "and stationary B have identical native turn/state and world stickers")

    # B' rotates the U/D axis to an R/L axis if the reference itself turns
    # by a quarter about the F/B axis; it leaves F/B as an axis.
    for sense in (-1, 1):
        r = quarter(NORMAL["B"], sense)
        print(f"B-axis reference quarter {sense:+}: U normal -> "
              f"{BY_NORMAL[apply(r, NORMAL['U'])]}, F normal -> "
              f"{BY_NORMAL[apply(r, NORMAL['F'])]}")

    current = ("F", "F'", "B", "F", "F'", "B'", "F", "F'")
    codes, changes = simulate(current, IDENTITY)
    print("current F sequence predicted codes/reference-changing:", codes, changes)
    assert codes == [0, 1, 0, 0, 1, 1, 0, 1]
    assert changes == ["B", "B'"]

    stateful = ("B'", "U", "U'", "B")
    codes, changes = simulate(stateful, IDENTITY)
    print("B' U U' B predicted codes/reference-changing:", codes, changes)
    assert codes == [1, 4, 5, 0]
    assert changes == ["B'", "U", "U'", "B"]

    # A -90 degree initial native-to-body orientation about physical U maps
    # native preferred F/U/R onto physical L/U/F, respectively.
    earlier_frame = quarter(NORMAL["U"], -1)
    print("earlier-frame preferred faces:", {
        face: BY_NORMAL[apply(earlier_frame, NORMAL[face])] for face in ("F", "U", "R")
    })
    six_face = tuple(move for face in "FURBDL" for move in (face, face + "'"))
    codes, changes = simulate(six_face, earlier_frame)
    print("six-face predicted codes/reference-changing:", codes, changes)
    assert codes == [4, 5, 2, 3, 0, 1, 4, 5, 2, 3, 0, 1]
    assert changes == ["R", "R'", "B", "B'", "D", "D'"]
    print("fixed native-color mapping plus rotated initial frame preserves "
          "same physical solved color frame:",
          permute_state(SOLVED, earlier_frame) == SOLVED)


def report_corner_constraints() -> None:
    corners = list(product((-1, 1), repeat=3))
    def corner_name(position: Vec) -> str:
        x, y, z = position
        return ("U" if y > 0 else "D") + ("R" if x > 0 else "L") + ("F" if z > 0 else "B")
    def included(position: Vec, face: str) -> bool:
        return dot(position, NORMAL[face]) == 1
    six_face = [p for p in corners if all(included(p, f) for f in "RBD")
                and not any(included(p, f) for f in "FUL")]
    after_b_prime = quarter(NORMAL["B"], +1)
    b_prime_u = [p for p in corners if included(p, "B") and included(p, "D")
                 and included(apply(after_b_prime, p), "U")]
    print("corner sensitive to R/B/D, not F/U/L:", [corner_name(p) for p in six_face])
    print("corner moved into U by B':", [corner_name(p) for p in b_prime_u])
    print("single fixed corner satisfying both:", [corner_name(p) for p in set(six_face) & set(b_prime_u)])


def self_check() -> None:
    assert len(ROTATIONS) == 24
    assert len(set(ROTATIONS)) == 24
    assert len(STICKERS) == len(STICKER_INDEX) == 24
    assert len(D4) == 8
    assert all(turn(turn(SOLVED, face), face, -1) == SOLVED for face in FACES)
    assert all(gauge_state(SOLVED, rotation) == SOLVED for rotation in ROTATIONS)
    assert S0 == tuple(group for group in range(6) for _ in range(4))
    assert all(len(state) == 24 for state in (S0, S1, S2, S4, A_PRE))
    marker_state = tuple(range(24))
    for face in FACES:
        for direction in (-1, 1):
            candidate, frame, _ = physical_step(marker_state, IDENTITY, face, direction)
            assert permute_state(candidate, frame) == turn(marker_state, face, direction)
    for frame in ROTATIONS:
        for face in FACES:
            candidate, new_frame, _ = physical_step(marker_state, frame, face, 1)
            physical = permute_state(marker_state, frame)
            assert permute_state(candidate, new_frame) == turn(physical, face, 1)


if __name__ == "__main__":
    self_check()
    report_geometry()
    report_corner_constraints()
    report_captures()
