"use client";

/**
 * 2D billboard limbs for locked tracks — cartoon arms + legs that hang off
 * the detected object's bbox so still-life reads as a living character.
 *
 * Pure SVG (no PNG atlas). Sized from the element-space body box; origin is
 * the face-anchor group, so callers pass the box center as an offset from
 * that anchor. Idle sway is CSS; speaking just speeds the same motion.
 */

export type ObjectLimbsProps = {
  /** Box center X relative to the face-anchor group origin (element px). */
  offsetX: number;
  /** Box center Y relative to the face-anchor group origin (element px). */
  offsetY: number;
  /** Object bbox width in element px. */
  width: number;
  /** Object bbox height in element px. */
  height: number;
  /** Motion lean from the tracker (deg) — limbs tilt with the body. */
  tilt?: number;
  /** Faster sway while the track is speaking. */
  speaking?: boolean;
};

const MIN_BODY_PX = 28;
const LIMB_FILL = "#ff89be";
const LIMB_STROKE = "rgba(255,255,255,0.6)";

export function ObjectLimbs({
  offsetX,
  offsetY,
  width,
  height,
  tilt = 0,
  speaking = false,
}: ObjectLimbsProps) {
  if (
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width < MIN_BODY_PX ||
    height < MIN_BODY_PX
  ) {
    return null;
  }

  // Limb length scales with the shorter body side so tiny objects don't
  // sprout giant arms, and tall bottles don't get stubby sticks.
  const unit = Math.min(width, height);
  const armLen = Math.max(18, unit * 0.55);
  const legLen = Math.max(22, unit * 0.65);
  const thick = Math.max(7, Math.min(16, unit * 0.14));
  const hand = thick * 1.15;
  const foot = thick * 1.35;

  // Shoulder / hip attach points: inset from the bbox edges so limbs read
  // as growing out of the object, not floating beside it.
  const insetX = width * 0.08;
  const shoulderY = -height * 0.12;
  const hipY = height * 0.42;
  const leftX = -width / 2 + insetX;
  const rightX = width / 2 - insetX;

  const pace = speaking ? "0.55s" : "1.35s";

  return (
    <div
      className="pointer-events-none absolute left-0 top-0"
      style={{
        transform: `translate(${offsetX}px, ${offsetY}px) rotate(${tilt}deg)`,
        width: 0,
        height: 0,
      }}
      aria-hidden
    >
      <LimbJoint
        x={leftX}
        y={shoulderY}
        length={armLen}
        thick={thick}
        tip={hand}
        side="left"
        kind="arm"
        pace={pace}
        delay="0s"
      />
      <LimbJoint
        x={rightX}
        y={shoulderY}
        length={armLen}
        thick={thick}
        tip={hand}
        side="right"
        kind="arm"
        pace={pace}
        delay="0.12s"
      />
      <LimbJoint
        x={leftX + width * 0.12}
        y={hipY}
        length={legLen}
        thick={thick}
        tip={foot}
        side="left"
        kind="leg"
        pace={pace}
        delay="0.06s"
      />
      <LimbJoint
        x={rightX - width * 0.12}
        y={hipY}
        length={legLen}
        thick={thick}
        tip={foot}
        side="right"
        kind="leg"
        pace={pace}
        delay="0.18s"
      />
    </div>
  );
}

type LimbJointProps = {
  x: number;
  y: number;
  length: number;
  thick: number;
  tip: number;
  side: "left" | "right";
  kind: "arm" | "leg";
  pace: string;
  delay: string;
};

function LimbJoint({
  x,
  y,
  length,
  thick,
  tip,
  side,
  kind,
  pace,
  delay,
}: LimbJointProps) {
  // Arms hang outward-and-down; legs hang mostly straight down with a
  // small outward splay so the stance reads as "standing".
  const restDeg =
    kind === "arm"
      ? side === "left"
        ? -28
        : 28
      : side === "left"
        ? -8
        : 8;
  const animName =
    kind === "arm"
      ? side === "left"
        ? "limb-arm-l"
        : "limb-arm-r"
      : side === "left"
        ? "limb-leg-l"
        : "limb-leg-r";

  const svgW = thick * 2.4;
  const svgH = length + tip;

  return (
    <div
      className="absolute"
      style={{
        left: x,
        top: y,
        width: svgW,
        height: svgH,
        marginLeft: -svgW / 2,
        transformOrigin: "50% 0%",
        transform: `rotate(${restDeg}deg)`,
        filter: "drop-shadow(0 2px 4px rgba(40,10,40,0.28))",
      }}
    >
      {/* Inner node owns the sway animation so it can't clobber rest pose. */}
      <div
        style={{
          width: "100%",
          height: "100%",
          transformOrigin: "50% 0%",
          animation: `${animName} ${pace} ease-in-out infinite`,
          animationDelay: delay,
        }}
      >
        <svg
          width={svgW}
          height={svgH}
          viewBox={`0 0 ${svgW} ${svgH}`}
          fill="none"
        >
          <rect
            x={(svgW - thick) / 2}
            y={0}
            width={thick}
            height={length}
            rx={thick / 2}
            fill={LIMB_FILL}
            stroke={LIMB_STROKE}
            strokeWidth={1.2}
          />
          <ellipse
            cx={svgW / 2}
            cy={length + tip * 0.35}
            rx={tip * 0.55}
            ry={tip * 0.42}
            fill={LIMB_FILL}
            stroke={LIMB_STROKE}
            strokeWidth={1.1}
          />
        </svg>
      </div>
    </div>
  );
}
