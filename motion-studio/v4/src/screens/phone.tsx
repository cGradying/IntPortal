// Everything drawn inside the Shape while it is a phone.
import React from "react";
import { PH } from "../theme";
import type { Box } from "../types";
import { Center, Splash } from "../phrases/p1";
import { Island, StatusBar, TabBar, phoneOn, theme } from "./chrome";
import { Today } from "./today";
import { Grades } from "./grades";
import { Notes } from "./notes";
import { Themes } from "./themes";
import { Sis } from "./sis";

export const PhoneInside: React.FC<{ t: number; box: Box }> = ({ t, box }) => {
  if (!phoneOn(t)) return <Center box={box} w={PH.w} h={PH.h}><Themes t={t} box={box} /></Center>;
  const th = theme(t);
  return (
    <>
      <Splash t={t} box={box} />
      <Center box={box} w={PH.w} h={PH.h}>
        <StatusBar t={t} th={th} />
        <Today t={t} />
        <Grades t={t} />
        <Notes t={t} />
        <Themes t={t} box={box} />
        <Sis t={t} />
        <TabBar t={t} th={th} on={[[24, 110.6], [127.6, 131.8], [137.2, 151.4]]} />
        <Island t={t} />
      </Center>
    </>
  );
};
