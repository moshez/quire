(* theme.dats — Theme proof constructors.
 *
 * Each function constructs the proof that its theme's colors satisfy
 * all WCAG contrast, polarity, comfort, and warmth requirements.
 * The ATS2 constraint solver verifies the inequalities at compile time.
 * If any color constant is changed and breaks a constraint, the build fails.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./theme.sats"

(* Light theme: bg/fg contrast 34:1, bg/link 8.6:1, chrome 18.7:1,
 * light polarity (bg >= 5000, fg <= 2000). *)
implement verify_light_theme() = (
  LIGHT_THEME_OK(
    AA_PASS(),      (* bg/fg: (9547+50)*10=95970 >= 45*(232+50)=12690 *)
    AA_PASS(),      (* bg/link: (9547+50)*10=95970 >= 45*(1066+50)=50220 *)
    AA_PASS(),      (* chrome: (8773+50)*10=88230 >= 45*(423+50)=21285 *)
    LIGHT_POL()     (* bg=9547 >= 5000, fg=232 <= 2000 *)
  ) | ()
)

(* Dark theme: fg/bg contrast 14.1:1, link/bg 14.0:1, chrome 10.6:1,
 * dark polarity (bg <= 500, fg >= 1500),
 * comfort (max 15:1 to prevent halation). *)
implement verify_dark_theme() = (
  DARK_THEME_OK(
    AA_PASS(),      (* fg/bg: (2918+50)*10=29680 >= 45*(160+50)=9450 *)
    AA_PASS(),      (* link/bg: (2886+50)*10=29360 >= 45*(160+50)=9450 *)
    AA_PASS(),      (* chrome: (2918+50)*10=29680 >= 45*(252+50)=13590 *)
    DARK_POL(),     (* bg=160 <= 500, fg=2918 >= 1500 *)
    COMFORT_PASS(), (* fg/bg: (2918+50)*10=29680 <= 150*(160+50)=31500 *)
    COMFORT_PASS()  (* chrome: (2918+50)*10=29680 <= 150*(252+50)=45300 *)
  ) | ()
)

(* Sepia theme: bg/fg contrast 22.2:1, bg/link 12.5:1, chrome 20.2:1,
 * light polarity, sepia warmth (R-B = 240-210 = 30, in range 15-50). *)
implement verify_sepia_theme() = (
  SEPIA_THEME_OK(
    AA_PASS(),      (* bg/fg: (7977+50)*10=80270 >= 45*(312+50)=16290 *)
    AA_PASS(),      (* bg/link: (7977+50)*10=80270 >= 45*(594+50)=28980 *)
    AA_PASS(),      (* chrome: (7251+50)*10=73010 >= 45*(312+50)=16290 *)
    LIGHT_POL(),    (* bg=7977 >= 5000, fg=312 <= 2000 *)
    SEPIA_WARM()    (* R=240, B=210, diff=30, 15 <= 30 <= 50 *)
  ) | ()
)
