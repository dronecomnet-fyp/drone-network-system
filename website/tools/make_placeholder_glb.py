#!/usr/bin/env python3
"""Generate a simple placeholder quadcopter GLB for the product 3D viewer.

Use this until a real scanned/CAD model is available. It builds a body,
four arms, and four rotor disks with trimesh and exports drone.glb.

    pip install trimesh numpy
    python make_placeholder_glb.py            # writes drone.glb here
    python make_placeholder_glb.py out.glb    # custom path

Then upload the .glb to a public Supabase Storage bucket and set the
product's specs.model_3d_url (or products.model_3d_url) to its public URL.
"""

import sys

import numpy as np
import trimesh


def build_drone() -> trimesh.Trimesh:
    parts = []

    # Central body.
    body = trimesh.creation.box(extents=(0.16, 0.16, 0.05))
    body.visual.face_colors = [40, 44, 52, 255]
    parts.append(body)

    arm_len = 0.22
    for sign_x, sign_y in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        # Arm: a thin box from the body out to the motor.
        arm = trimesh.creation.box(extents=(arm_len, 0.03, 0.02))
        # Rotate 45 degrees so arms point to the corners.
        angle = np.deg2rad(45 if sign_x * sign_y > 0 else -45)
        arm.apply_transform(trimesh.transformations.rotation_matrix(angle, [0, 0, 1]))
        mid = np.array([sign_x, sign_y, 0.0]) * (arm_len / 2) / np.sqrt(2)
        arm.apply_translation(mid)
        arm.visual.face_colors = [60, 66, 78, 255]
        parts.append(arm)

        # Rotor disk at the end of the arm.
        rotor = trimesh.creation.cylinder(radius=0.09, height=0.008, sections=32)
        tip = np.array([sign_x, sign_y, 0.02]) * arm_len / np.sqrt(2)
        rotor.apply_translation(tip)
        rotor.visual.face_colors = [185, 28, 28, 200]
        parts.append(rotor)

    return trimesh.util.concatenate(parts)


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "drone.glb"
    drone = build_drone()
    drone.export(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
