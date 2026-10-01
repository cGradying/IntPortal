// Vector arrow, black with a white 1.5px keyline. Screen space (constant size).
import React from "react";

export const Cursor: React.FC<{ x: number; y: number; press: number }> = ({ x, y, press }) => {
  const s = 1 - 0.08 * press;
  return (
    <svg width={44} height={44} viewBox="0 0 22 22" style={{
      position: "absolute", left: 0, top: 0, overflow: "visible",
      transform: `translate(${(x - 4).toFixed(2)}px, ${(y - 3).toFixed(2)}px) scale(${s.toFixed(4)})`, transformOrigin: "4px 3px",
    }}>
      <path d="M2.2 1.6 18.2 9.8l-7 1.8-3.4 6.6z" fill="#0B0B0C" stroke="#FFFFFF" strokeWidth={1.5 / 2} strokeLinejoin="round" />
    </svg>
  );
};
