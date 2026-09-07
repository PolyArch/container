# Container Support Matrix

This file is the source of truth for `container matrix`. The command renders
the status portion as a compact terminal table, while this document retains the
full smoke commands, limitations, and evidence. The OS columns record shell
smoke support. The GUI column records whether a GUI command can initialize
through the dedicated `container gui` Xvnc image.

Status terms:

- `ok`: the smoke command starts far enough to validate runtime dependencies;
- `partial`: a documented launcher or subset works, but another common path
  still has a known limitation;
- `blocked`: the blocker is outside the runtime image, such as required site
  configuration, missing entitlement, or modulefile semantics for that OS;
- `not yet validated`: no maintained smoke result has been recorded yet;
- `n/a`: the tool has no meaningful GUI smoke in this matrix.

The OS columns use representative images for each family: CentOS 7 for EL7,
AlmaLinux 8 for EL8, AlmaLinux 9 for EL9, and AlmaLinux 10 for EL10. EL8/EL9
are the primary supported enterprise runtimes for the current installed tool
set. EL7 uses Environment Modules 5.3 in the maintained image so current
modulefiles load correctly, but many modern vendor binaries require newer
GLIBC or library ABI baselines than EL7 can safely provide. EL10 is usable for
most tools but still exposes some vendor-specific compatibility gaps.

| Vendor / Tool / Version | EL7 Shell | EL8 Shell | EL9 Shell | EL10 Shell | GUI |
| --- | --- | --- | --- | --- | --- |
| Synopsys / Design Compiler `syn/Y-2026.03-SP2` | blocked: requires GLIBC 2.18-2.28 | ok: `dc_shell -version` | ok: version, licensed startup/exit, and `DW01_add` elaboration with DWBB 202603.2 | ok: `dc_shell -version` | ok: Design Vision TopLevel window via EL9 runtime and `container gui` |
| Synopsys / TestMAX `testmax/Y-2026.03-SP2` | blocked: requires GLIBC 2.18-2.28 | ok: `testmax_shell`, `dft_shell`, and legacy `tmax` version paths | ok: all version paths plus licensed `testmax_shell` and legacy `tmax` startup/exit | ok: all version paths; legacy `tmax` uses child-scoped vendor FreeType compatibility | ok: TestMAX BlockWindow and shell console via EL9 runtime and `container gui` |
| Synopsys / TestMAX ALE `ale/Y-2026.03-SP2` | blocked: requires GLIBC 2.28 and ncurses 6 | ok: `ale_shell -version`, `ale_tran -help` | ok: `ale_shell -version`, `ale_tran -help` | ok: `ale_shell -version`, `ale_tran -help` | n/a |
| Synopsys / DFTView `dftview/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `dftview -version` | ok: `dftview -version` | ok: `dftview -version` | ok: DFTView main window via EL9 runtime and `container gui` |
| Synopsys / VCAP `vcap/Y-2026.03-SP2` | blocked: requires GLIBC 2.25/2.27 | partial: `vcap -version` prints the correct release banner but returns 255 because arguments are interpreted as a command file | partial: correct Y-2026.03-SP2 release banner with the same nonzero command-file behavior | partial: correct Y-2026.03-SP2 release banner with the same nonzero command-file behavior | n/a |
| Synopsys / VTRAN `vtran/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `vtran -version` | ok: `vtran -version` | ok: `vtran -version` | n/a: VUI is the installed graphical front end |
| Synopsys / VUI `vui/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `vui -version` | ok: `vui -version` | ok: `vui -version` | ok: Initial Setup and Context-Sensitive Help windows via EL9 runtime and `container gui` |
| Synopsys / Yield Explorer `yieldexplorer/W-2025.06-SP2` | ok: startup reaches display initialization with locale warnings | ok: startup reaches display initialization | ok: startup reaches display initialization | ok: startup reaches display initialization | ok: W-2025.06-SP2 main window and offline default project via EL9 runtime and `container gui` |
| Synopsys / DSO.ai `dsoai/Y-2026.03-SP3` | blocked: requires GLIBC 2.28 | ok: `dso_shell -help` | ok: `dso_shell -help` | ok: `dso_shell -help` | ok: DSO.ai database/session window via EL9 runtime and `container gui` |
| Synopsys / Avalon `avalon/X-2025.09-SP2` | not yet validated | ok: `licenseinfo -h` | ok: `licenseinfo -h` and Qt startup through `container gui` | not yet validated | partial: Avalon reached Qt initialization through the managed EL9 Xvnc display; no project was opened |
| Synopsys / Core Tools `coretools/Y-2026.03-SP3` | blocked: GLIBC baseline not validated on EL7 | ok: `coreAssembler -help` | ok: `coreAssembler -help` | ok: `coreAssembler -help` | n/a: command-line core tool launcher |
| Synopsys / Certitude `certitude/Y-2026.03-SP2` | not yet validated | partial: executable reaches Qt display initialization; headless `certitude -help` needs DISPLAY | ok: `certitude version`, executable startup, and `certitude_gui` through `container gui` | blocked: requires OpenSSL 1.1 compatibility ABI unavailable in the maintained EL10 image | ok: GUI process stayed running through the managed EL9 Xvnc display; no project or license checkout was requested |
| Synopsys / Embed-It! `embedit/Y-2026.06-SP1` | blocked: native library requires GLIBC 2.27 | ok: `integrator -help`, `integrator -version` | ok: `integrator -help`, `integrator -version` | ok: `integrator -help`, `integrator -version` | partial: Agreement Confirmation rendered via EL9 runtime and `container gui`; legal acknowledgment was not accepted by the maintenance agent |
| Synopsys / ESP `esp/Y-2026.03-SP2` | blocked: missing EL7 `libtinfo.so.6` ABI | ok: `esp_shell` startup/exit | ok: `esp_shell` startup/exit | ok: `esp_shell` startup/exit | n/a: the current binary rejects `-gui` and exposes no GUI command |
| Synopsys / Fusion Compiler `fusioncompiler/Y-2026.03-SP1` | blocked: requires GLIBC 2.18-2.28 and XCRYPT 2.0 | ok: `fc_shell -version` | ok: version plus SAED14 `initial_map` of `DW_lzd`, forced `DW_div/cla`, and representative `DW_fp_*` with DWBB 202603.1 | ok: `fc_shell -version` | ok: Fusion Compiler BlockWindow via EL9 runtime and `container gui` |
| Synopsys / VCS `vcs/Y-2026.03-SP1` | ok: `vcs -full64` | ok: `vcs -full64` | ok: `vcs -full64` | ok: `vcs -full64` | n/a |
| Synopsys / Low Power Verification Tools `mvtools/K-2015.09-SP1` | blocked: inherited `C.UTF-8` locale aborts old binary | ok: `mvcmp -help` | ok: `mvcmp -help` | ok: `mvcmp -help` | n/a |
| Synopsys / DesignWare Memory Models `dmm/2002.12` | ok: `sl_admin -help` with locale warnings | ok: `sl_admin -help` | ok: `sl_admin -help` | blocked: missing old 32-bit runtime | n/a |
| Synopsys / SmartModel Library and DW VIP `dw_vip_sm/2009.06` | ok: `swiftcheck -u`, `sl_admin -help` with locale warnings | ok: `swiftcheck -u`, `sl_admin -help` | ok: `swiftcheck -u`, `sl_admin -help` | partially ok: `swiftcheck -u`; `sl_admin` blocked by missing `libpng12.so.0` | GUI not yet validated |
| Synopsys / Laker ADP `laker_adp/2015.03` | ok: starts to DISPLAY check | ok: starts to DISPLAY check | ok: starts to DISPLAY check | blocked: missing `libpng12.so.0` | GUI not yet validated |
| Synopsys / SiliconSmart `siliconsmart/V-2023.12-SP5` | ok: `siliconsmart -v` with locale warnings | ok: `siliconsmart -v` | ok: `siliconsmart -v` | blocked: missing `libpng12.so.0` | ok: `siliconsmart -help` via EL9 runtime and `container gui` |
| Synopsys / ML Platform `cmlp/T-2022.03` | ok: `mlp --help` with locale warnings | ok: `mlp --help` | ok: `mlp --help` | ok: `mlp --help` | n/a |
| Synopsys / VC ML Platform `vc_ml_platform/2019.06` | ok: `mlp --help` with locale warnings | ok: `mlp --help` | ok: `mlp --help` | ok: `mlp --help` | n/a |
| Synopsys / Verdi `verdi/Y-2026.03-SP1` | blocked: GLIBC > EL7 | ok: `verdi -id` plus supplementary link | ok: `verdi -id` plus supplementary link | ok: `verdi -id` plus supplementary link | ok: `verdi` via EL9 runtime and `container gui` |
| Synopsys / Formality `fm/Y-2026.03-SP2` | blocked: requires GLIBC 2.25-2.28 | ok: `fm_shell -version` and shell startup/exit | ok: `fm_shell -version` and shell startup/exit | ok: `fm_shell -version` and shell startup/exit | ok: Formality main window via EL9 `fm_shell -gui` and `container gui` |
| Synopsys / IC Validator `icvalidator/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: complete `icv -V` subengine probe | ok: complete `icv -V` subengine probe | ok: complete `icv -V` subengine probe | ok: VUE Load Results window via EL9 `icv_vue` and `container gui` |
| Synopsys / NanoTime `nt/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `nt_shell -version` | ok: `nt_shell -version` and licensed startup/exit | ok: `nt_shell -version` | blocked: standalone `nt_shell -gui` requires an unavailable `amsenv`; official Custom Compiler integration is enabled |
| Synopsys / PrimePower RTL `pprtl/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `pprtl -version` | ok: `pprtl -version` and licensed startup/exit | ok: `pprtl -version` with EL10-scoped vendor FreeType compatibility path | n/a |
| Synopsys / IC Compiler II `icc2/Y-2026.03-SP1` | blocked: requires GLIBC 2.18-2.28 and XCRYPT 2.0 | ok: `icc2_shell -version` | ok: version and licensed startup/exit | ok: `icc2_shell -version` | ok: IC Compiler II BlockWindow via EL9 runtime and `container gui` |
| Synopsys / Library Compiler `lc/Y-2026.03-SP2` | blocked: requires GLIBC 2.18 and 2.25-2.28 | ok: `lc_shell -version` | ok: version and licensed startup/exit | ok: `lc_shell -version` | n/a: `lc_shell` exposes no GUI option |
| Synopsys / RTL Architect `rtla/Y-2026.03-SP1` | blocked: requires GLIBC 2.18/2.22/2.25/2.27/2.28 and XCRYPT 2.0 | ok: `rtl_shell -version` and `lm_shell -version` | ok: versions plus licensed RTL Architect and Library Manager startup/exit | ok: `rtl_shell -version` and `lm_shell -version` | ok: RTL Architect BlockWindow via EL9 runtime and `container gui` |
| Synopsys / ZeBu IP `zebu_ip/W-2025.06` with DRAM IP W-2025.06-SP1 | ok: module load, data visibility, and SP1 alias resolution | ok: module load, data visibility, and SP1 alias resolution | ok: module load, data visibility, and SP1 alias resolution | ok: module load, data visibility, and SP1 alias resolution | n/a: data/IP library |
| Synopsys / Prime `prime/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `pt_shell -version` and `primepower -version` | ok: version checks plus licensed PrimeTime and PrimePower startup/exit | ok: `pt_shell -version` and `primepower -version` | ok: `pt_shell -gui` via EL9 runtime and `container gui` |
| Synopsys / PrimeLib `primelib/Y-2026.03-SP2` | blocked: requires GLIBC 2.18 and 2.25-2.28 plus newer zlib ABI | ok: licensed `primelib -version` | ok: licensed `primelib -version` | ok: licensed `primelib -version` | n/a: the installed command is a Tcl shell and exposes no GUI option |
| Synopsys / QuickCap `quickcap/Y-2026.03-SP2` | blocked: missing `libtirpc.so.3` | ok: `quickcap` usage | ok: `quickcap`/`qtfx` usage and `qtfx -licenses` | ok: `quickcap` usage | n/a: `-x` visualization requires an input model and no standalone GUI or bundled smoke model is provided |
| Synopsys / StarRC `starrc/Y-2026.03-SP2` | blocked: no EL7 `libncurses.so.6` ABI | ok: `StarXtract -version` | ok: `StarXtract -version` and licensed startup/exit | ok: `StarXtract -version` | ok: StarRC LayoutWindow via EL9 runtime and `container gui` |
| Synopsys / ProGen `progen/V-2023.12-2` | ok: `progen -help` with locale warnings | ok: `progen -help` | ok: `progen -help` | ok: `progen -help` | n/a |
| Synopsys / Proteus LX `proteus_lx/V-2023.12-2` | ok: `proteus -version` with locale warnings | ok: `proteus -version` | ok: `proteus -version` | ok: `proteus -version` | n/a |
| Synopsys / Proteus WorkBench LX `proteus_wb_lx/V-2023.12-2` | ok: `pwbRecipeRun` reaches usage with locale warnings | ok: `pwbRecipeRun` reaches usage | ok: `pwbRecipeRun` reaches usage | ok: `pwbRecipeRun` reaches usage | blocked: `fwDebugger` reaches server-port connection handling via EL9 runtime and `container gui`, but full validation needs a real PWB server endpoint |
| Synopsys / HSPICE `hspice/Y-2026.03-SP1` | blocked: vendor requires GLIBC 2.28+ | ok | ok | ok | n/a |
| Synopsys / FPGA Synplify Pro `fpga/Y-2026.03-SP1` | blocked: GLIBC > EL7 | ok | ok | ok | ok: `synplify_pro` via EL9 runtime and `container gui` |
| Cadence / Virtuoso IC `IC/251` Hotfix 25.10.070 | blocked: no EL7 `libmvec.so.1` ABI | ok: `virtuoso -W` reports IC25.1-64b.ISR7.34 | ok: version and licensed GUI startup | ok: `virtuoso -W` reports IC25.1-64b.ISR7.34 | ok: Virtuoso Studio IC25.1 CIW via EL9 runtime and `container gui` |
| Cadence / Xcelium `XCELIUM/2603` | blocked: GLIBC > EL7 | ok: `xrun` 26.03-s005 compile/run | ok: `xrun` 26.03-s005 compile/run | partial: default `xrun` wrapper not usable in this smoke | ok: `simvision` 26.03-s005 via EL9 runtime and `container gui` |
| Cadence / Protium X3 PTM `PTM/2602` | blocked: Oracle/CentOS require newer GLIBC and library ABIs | ok: Alma/Rocky `xeCompile` startup/exit, all four version paths, and `ProtiumX3_Implementation_Debug` checkout | ok: Alma/Rocky `xeCompile` startup/exit, all four version paths, and license checkout | ok: Alma/Rocky `xeCompile` startup/exit, all four version paths, and license checkout | not yet validated: hardware/debug GUI needs a real Protium X3 target |
| Cadence / IXCOM and HDLICE `IXCOM/2607` | blocked: IXCOM requires newer GLIBC and HDLICE requires `libtirpc.so.3` | ok: Alma/Rocky `ixcom` and `hdlice` 26.07.607 | ok: Alma/Rocky `ixcom` and `hdlice` 26.07.607 | ok: Alma/Rocky `ixcom` and `hdlice` 26.07.607 | n/a: command-line integration tools |
| Cadence / SPB Allegro and OrCAD `SPB/251` Hotfix 25.10.050 | not yet validated | ok: Allegro wrapper help | ok: Allegro wrapper help | not yet validated | ok: Allegro X Designer 25.1-S050 main window via EL9 runtime and `container gui` |
| Cadence / Sigrity and Celsius `SIGRITY/20251` Hotfix 25.10.400 | not yet validated | ok: command paths and 25.1.4 build manifest | ok: command paths and 25.1.4 build manifest | not yet validated | ok: licensed PowerSI II Layout Workbench 400 via EL9 runtime and `container gui` |
| Cadence / Helium `HELIUM/2602` | not yet validated | not yet validated | ok: `helium -version` reports 26.02-s001 | not yet validated | ok: Helium Launcher via EL9 runtime and `container gui`; screenshot captured through the local maintenance venv |
| Cadence / Incisive `INCISIVE/152` | ok: `irun`/`ncsim` with locale warnings | ok: `irun`/`ncsim` | ok: `irun`/`ncsim` | blocked: missing old 32-bit runtime | ok: `simvision` via EL9 runtime and `container gui`; CUA screenshot captured through the local maintenance venv |
| Cadence / Liberate Characterization Portfolio `LIBERATE/261` Hotfix 26.10.062-HF2 | blocked: missing `libreadline.so.7` | ok: `liberate -version` reports 26.1.0.062 | ok: `liberate -version` reports 26.1.0.062 | ok: `liberate -version` reports 26.1.0.062 | n/a: the installed launcher exposes Tcl/Python command modes and no standalone GUI option |
| Cadence / Stratus `STRATUS/2601` | blocked: GLIBC > EL7 | ok: 26.01-s003 | ok: 26.01-s003 | ok: 26.01-s003 | ok: `stratus_ide` via EL9 runtime and `container gui` |
| Cadence / Digital Design Implementation `DDI/261` | blocked: no EL7 `libmvec.so.1` | ok | ok | ok: Genus shell path | ok: Genus/Innovus GUI via EL8 runtime and `container gui`; EL9 GUI segfaults |
| Cadence / Cerebrus AI optimization `CEREBRUS/261` + `DDI/261` | not yet validated | not yet validated | ok: official `outer_control_flow` RAK completed through Genus synthesis and Innovus placement; best placement cost improved 9% | not yet validated | n/a: coordinated batch flow |
| Cadence / Midas safety verification `MIDAS/2603` | not yet validated | not yet validated | ok: GUI shell reports Midas USF 26.03.002 | not yet validated | ok: `midas` via EL9 runtime and `container gui` |
| Cadence / EMX `EMX/20261` | not yet validated | not yet validated | ok: `emx --help`, EMX 2026.1.0 | not yet validated | ok: bundled ParaView 5.13.1 via EL9 runtime and `container gui` |
| Cadence / Spectre `SPECTRE/251` Hotfix 10.12.442 | blocked: no EL7 `libmvec.so.1` | ok: `spectre -W` reports 25.1.0.442.isr12 | ok: `spectre -W` reports 25.1.0.442.isr12 | ok: `spectre -W` reports 25.1.0.442.isr12 | n/a |
| Cadence / Pegasus `PEGASUS/251` | blocked: GLIBC > EL7 | ok: 25.13-s012 | ok: 25.13-s012 | ok: 25.13-s012 | ok: `pegasusgui` via EL9 runtime and `container gui` |
| Cadence / Pegasus DFM `PEGASUSDFM/261` | not yet validated | not yet validated | ok: `PEGASUSDFMVersion` 26.10.000 and LPA 26.1.0-p048 | not yet validated | blocked: documented Design Review needs the separately supplied `k2_viewer` and real design data |
| Cadence / Modus `MODUS/251` | ok | ok | ok | ok | ok: `modus -gui` via EL8/EL9 runtime and `container gui` |
| Cadence / Signoff Suite `SSV/261` | blocked: no EL7 `libreadline.so.7` | ok | ok | partial: Tempus shell path not usable in this smoke | ok: Tempus GUI via EL8 runtime and `container gui`; EL9 GUI segfaults |
| Cadence / Verisium Manager AGL `VERISIUMMGRAGL/2603` | ok: 26.07-a020 | ok: 26.07-a020 | ok: 26.07-a020 | ok: 26.07-a020 | blocked: `vmanager` requires a server profile name or URL before GUI launch |
| Intel Altera / Quartus Prime Pro `26.1` | ok | ok | ok | ok | ok: `quartus` via EL9 runtime and `container gui` |
| Intel / oneAPI Toolkit `intel/oneapi/2026.1` with oneDAL 2026.1 | blocked: compiler requires GLIBC 2.18/2.28 | ok: `icpx`+MKL, `ifx`, 2-rank MPI, and oneDAL sample | ok: `icpx`+MKL, `ifx`, 2-rank MPI, and oneDAL sample | ok: `icpx`+MKL, `ifx`, 2-rank MPI, and oneDAL sample | ok: VTune Profiler 2026.2 via EL9 runtime and `container gui`; oneDAL is a library |
| Intel / Advisor `intel/advisor/2026.0` | ok: `advixe-cl --version` with locale warnings | ok: `advixe-cl --version` | ok: `advixe-cl --version` | ok: `advixe-cl --version` | ok: Advisor 2026.0 Welcome and Project Navigator via EL9 runtime and `container gui` |
| AMD Xilinx / Vivado `2026.1` | ok | ok | ok | ok | ok: `vivado` via EL9 runtime and `container gui` |
| Achronix / ACE `10.5.2` | ok | ok | ok | ok | ok: `ace` via EL9 runtime and `container gui` |
| Arm / Fast Models `ARM/FastModels/11.31` | blocked: EL7 system `libstdc++` lacks required GLIBCXX/CXXABI symbols | blocked: EL8 system `libstdc++` lacks `GLIBCXX_3.4.26` | ok: `simgen --version` | ok: `simgen --version` | not yet validated |
| Arm / Fast Models `ARM/FastModels/11.26` | blocked: EL7 system `libstdc++` lacks required GLIBCXX/CXXABI symbols | ok: `model_shell64 --version`, `simgen --version` | ok: `model_shell64 --version`, `simgen --version` | ok: `model_shell64 --version`, `simgen --version` | not yet validated |
| Open source / Open MPI `openmpi/5.0.10` | blocked: bundled libevent requires GLIBC 2.25+ | ok: 2-rank C MPI smoke | ok: 2-rank C MPI smoke | ok: 2-rank C MPI smoke | n/a |
| Open source / Go `go/1.27.0` | ok: `go run` with locale warnings | ok: `go run` | ok: `go run` | ok: `go run` | n/a |
| Open source / Node.js `nodejs/24.20.0` | blocked: official binary requires newer GLIBC/libstdc++ ABI than EL7 | ok: Node 24.20.0, npm/npx 11.19.0, corepack, JavaScript smoke | ok: Node 24.20.0, npm/npx 11.19.0, corepack, JavaScript smoke | ok: Node 24.20.0, npm/npx 11.19.0, corepack, JavaScript smoke | n/a |
| Benchmark / SPEC CPU2026 `SPEC/CPU2026/1.0.1` | blocked: bundled `specperl` requires newer GLIBC/libxcrypt ABI than EL7 | ok: `runcpu --version` | ok: `runcpu --version` | ok: `runcpu --version` | n/a |
| Open source / Lean `lean4/4.33.1` | ok: Lean theorem smoke and `lake --version` with locale warnings | ok: Lean theorem smoke and `lake --version` | ok: Lean theorem smoke and `lake --version` | ok: Lean theorem smoke and `lake --version` | n/a |
| Open source / SCons `scons/4.11.1` | blocked: SCons requires Python 3.7+, EL7 provides 3.6 | blocked: SCons requires Python 3.7+, EL8 provides 3.6 | ok: C build smoke with Python 3.9 | ok: C build smoke with Python 3.12 | n/a |
| Open source / Bazel `google/bazel/9.2.0` | blocked: GLIBC/libstdc++ ABI newer than EL7 | ok: minimal `genrule` build | ok: minimal `genrule` build | ok: minimal `genrule` build | n/a |
| Open source / Verilator `verilator/5.050` | blocked: EL8-built binary requires newer `libstdc++` ABI than EL7 | ok: minimal `--binary` Verilog smoke | ok: minimal `--binary` Verilog smoke | ok: minimal `--binary` Verilog smoke | n/a |
| Open source / Yosys `yosys/0.68` | blocked: EL8-built binary requires GLIBC 2.26/2.27 and newer libstdc++ ABI than EL7 | ok: Verilog synthesis with ABC and JSON output | ok: Verilog synthesis with ABC and JSON output | ok: Verilog synthesis with ABC and JSON output | n/a |
| Open source / OpenROAD `openroad/2026.08.28-2c569269719c` | blocked: EL8-built binary requires GLIBC 2.18/2.25/2.27/2.28 | ok: version and Tcl execution smoke | ok: version and Tcl execution smoke | ok: version and Tcl execution smoke | ok: OpenROAD 2c569269 main window via EL9 runtime and `container gui`; 1920x1080 CUA screenshot inspected |
| Open source / LLVM `llvm/22.1.8` | blocked: official binary requires newer GLIBC/libstdc++ ABI than EL7 | blocked: official binary requires GLIBC 2.34 / newer libstdc++ | blocked: official binary requires `GLIBCXX_3.4.30` | ok: `clang` compiles/runs a C smoke | n/a |
| Open source / RISC-V GNU Toolchain `riscv/2026.07.15` | blocked: official Ubuntu 24.04 binary requires newer GLIBC | blocked: official binary requires GLIBC 2.32-2.38 | blocked: official binary requires GLIBC 2.36/2.38 | ok: GCC 16.1.0 compiles an ELF64 RISC-V object | n/a |
| Open source / Z3 `z3/5.1.0` | blocked: EL8-built binary requires GLIBC 2.25/2.26 | ok: SMT solve and C API compile/run smoke | ok: SMT solve smoke | ok: SMT solve smoke | n/a |
| Open source / CIRCT firtool `firtool/1.157.0` | blocked: Z3/official firtool ABI newer than EL7 | blocked: official firtool binary requires GLIBC 2.38 | blocked: official firtool binary requires GLIBC 2.38 | ok: FIRRTL 4.0 to SystemVerilog smoke | n/a |
| NVIDIA / CUDA Toolkit `cuda/13.3.1` | ok: `nvcc` compiles a CUDA object with locale warnings | ok: `nvcc` compiles a CUDA object | ok: `nvcc` compiles a CUDA object | ok: `nvcc` compiles a CUDA object | n/a |
| MathWorks / MATLAB `R2026a` Update 4 | partial: `matlab -h` works; licensed runtime still requires newer GLIBC | partial: `matlab -h` works; no shared MATLAB license proof for container users | partial: `matlab -h` works; no shared MATLAB license proof for container users | partial: `matlab -h` works; no shared MATLAB license proof for container users | blocked: MATLAB desktop requires site-approved shared license or network license configuration |
| Open source / TeX Live 2026 package set `texlive/2026` | partial: `pdflatex` generates a PDF with locale warnings; bundled Biber 2.22 is blocked by its embedded Perl/PAR runtime | ok: `pdflatex` and Biber 2.22 generate a bibliography PDF | ok: `pdflatex` and Biber 2.22 generate a bibliography PDF | ok: `pdflatex` and Biber 2.22 generate a bibliography PDF | n/a |
| Accellera / UVM `uvm/2020.3.1` | ok: source library paths visible with locale warnings | ok: source library paths visible | ok: source library paths visible | ok: source library paths visible | n/a |

Update this matrix after each software install, modulefile publication, or
container dependency fix. Do not use pyrito or the NAS installation container as
evidence for runtime dependency support.
