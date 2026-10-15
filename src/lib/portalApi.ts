// How each portal signs in and counts tries, behind one shape, so the landing
// and the You screen never branch on a portal id. Not tested here: it only
// calls the core and writes `app`.
import { api, type Tries } from "./api";
import { fieldValues, type FormValues } from "./portals";
import { adopt, app, refreshLogins } from "./state.svelte";

export interface PortalApi {
  tries: () => Promise<Tries>;
  signIn: (v: FormValues) => Promise<void>;
}

export const portalApi: Record<string, PortalApi> = {
  sis: {
    tries: api.triesLeft,
    async signIn(raw) {
      const v = fieldValues(raw);
      const [y, m, d] = v.birthdate.split("-").map(Number);
      await adopt(await api.signIn({ student_number: v.student_number, birth_month: m, birth_day: d, birth_year: y, password: v.password }));
      await refreshLogins();
    },
  },
  mabini: {
    tries: api.mabiniTriesLeft,
    async signIn(raw) {
      const v = fieldValues(raw);
      app.mabini = await api.mabiniSignIn({ student_number: v.student_number, password: v.password });
      // The core opened this student's store; the tabs read its (maybe empty) SIS snapshot.
      await adopt(await api.snapshot());
      await refreshLogins();
    },
  },
};

export const portalApiFor = (id: string): PortalApi => portalApi[id] ?? portalApi.sis;
