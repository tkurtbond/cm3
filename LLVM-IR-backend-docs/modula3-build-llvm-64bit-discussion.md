# Modula-3: Build System History, a New Implementation, and Running cm3 on 64-bit Linux

An excerpt from a conversation. Each section gives the question as asked, followed by the answer. Inline source citations from the original replies have been removed; the source lists are kept.

---

## 1. The build system

**Question:**

> The language definition of M3 is fairly short by modern standards, but my impression from working with the last few times I tried is the build system was fairly complicated and that the original build system fell out of favor and was replaced by something else. Can you tell me about that?

**Answer:**

Your impression is mostly right, but the build language survived. What was replaced was the tool that ran it, and then the way the whole system gets installed.

**1. SRC's `m3build`.** In the original DEC SRC releases, m3build was a tiny program plus a set of predefined quake functions, meant as a replacement for make. It expected code to be organized into packages. It was run from a package's root directory and looked for the `m3makefile` in the `src` subdirectory. The build files were in an unusual language. m3makefiles are quake programs, an imperative language with variables, arrays, tables, conditionals, loops and procedures, though most of them are just sequences of calls to predefined procedures. Quake is probably what makes the system feel complicated: it was designed as a simple extension language, with building a general-purpose language explicitly not a goal.

**2. The `cm3` integrated builder.** Critical Mass changed this in version 4.0. That release revamped the builder so that all compiling and building is done through cm3, an integrated builder/compiler extended via a quake configuration file, cm3.cfg. So `m3build` as a separate tool went away, and the compiler itself became the builder. The `m3makefile` format and quake carried over: cm3 calls out to quake whenever it needs something specialized, like compiling C files or linking, and both cm3.cfg and m3makefiles are quake scripts. In practice, the `m3makefile` says what goes into a piece of the system, and `cm3.cfg` says how to do it on your platform. There are some conveniences. Typing `cm3` alone is shorthand for `cm3 -build`, and if there's no m3makefile it makes a best effort to build the Modula-3 files in the directory. Packages are installed with `cm3 -ship`, which puts a private package into the public repository, and that step may need special privileges on some systems.

**3. Forks.** Other branches of the family had their own bootstrapping. For example, the PM3 distribution says to run `make`, which builds bootstrap versions of the compiler and then uses it to rebuild and install all the libraries and programs. Which tools you meet depends on which distribution you tried.

**4. The recent installer.** If your attempts were within the last few years, the pain was probably in bootstrapping and installing rather than in m3makefiles. The newest release introduces a new installer, a simple source-based distribution containing a bootstrap compiler in C++. The documented flow is to build the bootstrap compiler, use it to build the full compiler, then use the full compiler to build and install the included Modula-3 libraries, driven by a provided Python script. The prerequisites are Python 3, CMake and a C++ compiler. The older route needed a prebuilt cm3 binary for your platform, which is a likely source of your trouble, since those binaries went stale.

**What I couldn't confirm.**

- I found no source describing why the community moved away from `m3build`, or a firm date for the transition beyond the 4.0 notes. That narrative is inferred from the release history.
- I believe the cm3 source tree also has helper scripts (such as `do-cm3.py`) that build sets of packages in order, but I didn't verify that.
- I don't know how much the current installer has simplified cross-platform configuration compared with hand-editing `cm3.cfg`.

If you remember where it broke for you (bootstrap, configuring `cm3.cfg`, or package dependencies), I can look at that specific part.

Sources:

- [m3build (SRC Modula-3 3.6)](https://softwarepreservation.computerhistory.org/modula3/archive/DEC_SRC/release-3.6-html/modula-3/html/m3build/m3build.html)
- [m3makefiles (SRC 3.6)](https://softwarepreservation.computerhistory.org/modula3/archive/DEC_SRC/release-3.6-html/modula-3/html/m3build/m3makefile.html)
- [CM3 quake documentation](https://www.cs.purdue.edu/homes/hosking/m3/help/cm3/quake.html)
- [CM3 release history](https://www.cs.purdue.edu/homes/hosking/m3/help/cm3/history.html)
- [CM3: Building Programs](https://www.cs.purdue.edu/homes/hosking/m3/help/cm3/m3build/m3build.html)
- [CM3: Packages](https://www.cs.purdue.edu/homes/hosking/m3/help/cm3/packages.html)
- [PM3 distribution](https://github.com/dragisha/pm3)
- [cm3 wiki: Getting Started](https://github.com/modula3/cm3/wiki/Getting-Started)
- [cm3 release d5.11.4](https://github.com/modula3/cm3/releases/tag/d5.11.4)

---

## 2. Approaching a new implementation

**Question:**

> If you were starting a new M3 implementation from scratch, or possibly using the existing front end and aiming for a LLVM backend how would you approach it?

**Answer:**

Short answer: I wouldn't start from scratch. The expensive and risky parts of a Modula-3 implementation are the front end semantics and the runtime, and the existing front end already separates cleanly from code generation. I'd also check first, because an LLVM backend already exists.

**What exists.** According to Bill Kalsow's history of the SRC compiler, the compiler switched from generating C to generating an internal intermediate language, defined as a set of method calls on a Modula-3 code generator object. That interface (called M3CG, from my memory of the sources) is the seam you'd target. In a 2017 status note on the mailing list, Rodney Bates reported that an LLVM backend passes all of the compiler tests in m3-sys/m3tests that the m3cc backend passes, but had been tried only on AMD64_LINUX. The note adds that it requires a local build of LLVM, and compiles noticeably slower than m3cc. I don't know its state today, so I'd start by finding that code in the cm3 repository.

**If I were doing it, in order:**

1. **Keep the front end (`m3front`) and the M3CG interface.** This gets you the type checker, generics, partial revelations, structural type equivalence, branded types and the rest of what makes the "short" language definition hard in practice. (These are my knowledge of the language, not from the searches.)
2. **Take over or revive the LLVM backend rather than rewriting it.** Pin it to one LLVM version, since LLVM's C++ API and IR change often. Emit textual IR or use the C API, not the C++ one, to cut the maintenance burden.
3. **Treat the runtime as a separate problem.** The backend is only part of the work. Garbage collection, threads, exception handling and stack scanning all interact with code generation. I'd keep conservative stack scanning (my understanding of what cm3 does today) at first and avoid LLVM's precise-GC statepoint machinery until everything else works.
4. **Keep the existing backend as a reference oracle.** The test suite passing under both m3cc and LLVM is how the 2017 work validated itself, and it's the right model. A subtle codegen difference between the two is usually a real bug in one of them.
5. **Be deliberate about nested procedures, debug info and bit-packed types.** The 2017 note mentions the two backends needing different orderings for unnesting nested procedures, which shows that even the shared front end leaks into backend design. You'd also want DWARF through LLVM, since debugging was historically a pain point. `BITS FOR` packing and alignment rules need careful mapping to LLVM types. These last two are my expectations, not findings.

**Cautions from the mailing list.** Norman Ramsey's opinion, relayed on the list in 2012, rated LLVM as having strong momentum and backing but a somewhat complex interface and a history of gaps. He was blunter about C-- as a target, saying everyone who tried compiling Modula-3 and similar languages through it eventually wrote their own native code generator. Kalsow's history also notes that debugging early C-generating Modula-3 compilers was difficult. So I'd weigh a C backend as a portability and bootstrap aid, not as the main target.

**If it truly is a from-scratch implementation,** I'd budget most of the effort for the type system and runtime, not parsing or codegen. I'd pick a native-hosted design (write the compiler in Modula-3, as SRC did) only if bootstrapping from the existing compiler is acceptable.

Two questions would change my advice. Are you after better optimization and platform coverage, or a cleaner, smaller implementation? And do you need to keep source compatibility with cm3's libraries?

Sources:

- [History of the SRC Modula-3 Compiler (Bill Kalsow)](https://softwarepreservation.computerhistory.org/modula3/doc/Kalsow-History_of_SRC_M3_Compiler.html)
- [m3devel: Status of the Cm3 llvm backend (2017)](https://m3lists.elegosoft.com/pipermail/m3devel/2017-August/036905.html)
- [m3devel: higher level m3cg? (2012)](https://m3lists.elegosoft.com/pipermail/m3devel/2012-August/034408.html)

---

## 3. Combining the three goals

**Question:**

> I'd be interested in all three

**Answer:**

I'm reading "all three" as your goals: better optimization and platform coverage, a cleaner and smaller implementation, and source compatibility with cm3's libraries. That's a defensible combination, but the goals pull against each other, so the order of work matters. Tell me if you meant something else.

**Where they conflict**

- Compatibility with cm3's libraries means keeping its runtime assumptions: the TEXT object model, threads, the collector, and exception semantics. That works against making the implementation smaller.
- A smaller implementation argues for dropping the weaker parts of the system, such as the legacy build machinery. That's mostly compatible with the other two goals if you drop tooling and not the language or library layer.
- Optimization and platform coverage come from LLVM, which is large and slow to build. That pulls against "smaller", at least in your build dependencies.

**A plan that serves all three**

1. **Phase 1: compatibility first, with the existing front end.** Reuse `m3front` and the M3CG seam, and get an LLVM backend passing the existing test suite (`m3-sys/m3tests`) alongside m3cc. Library compatibility comes nearly free here, because you're not touching the runtime or libraries. This is the lowest-risk way to get real platform coverage and optimization.

2. **Phase 2: shrink what surrounds the compiler.** Replace the install and build story (the bootstrap, `cm3.cfg` per-platform configuration, and the quake layering) with something simpler, without touching the language or library layer. This is where "cleaner and smaller" is cheapest to win, and the earlier build-system discussion suggests it's where people actually struggle. You could keep m3makefile and quake for compatibility while making the driver and config simpler.

3. **Phase 3: clean up the runtime selectively.** Once Phase 1 is stable, consider the harder changes: UTF-8-friendly text, the 16-bit WIDECHAR limits, precise GC through LLVM's mechanisms, and a leaner thread layer. Do these behind existing interfaces so library source stays compatible. They break compatibility most easily, so each should be opt-in and tested against the library suite.

**Decisions to make early**

- **Baseline version.** Pick a specific cm3 release as the compatibility target, since the codebase and libraries have drifted between forks (SRC, PM3, CM3).
- **LLVM dependency model.** Linking against a system LLVM keeps the footprint small but ties you to its release cadence. Vendoring a pinned version is easier to reason about but larger. I'd start by linking a system install and pinning a range.
- **Proof of progress.** Make "the compiler compiles itself under the new backend" the first milestone. It exercises generics, objects, threads, and the library surface all at once.

**Realistic scope.** Phase 1 depends heavily on the state of the existing LLVM backend, which I couldn't verify. If it's close to working, this is a project for one experienced person over a few months. If it has bit-rotted, expect more. Phases 2 and 3 are open-ended and best driven by what you actually hit using it.

Would you like me to dig into the cm3 repository for the LLVM backend's current state, so the Phase 1 estimate rests on facts?

---

## 4. Emitting LLVM IR instead of linking LLVM

**Question:**

> How about using LLVM IR, rather than linking LLVM directly?

**Answer:**

That's a good idea, and I'd probably choose it as the default. Emitting textual IR (`.ll` files) and handing it to LLVM's command-line tools decouples the compiler from LLVM's libraries.

The 2017 backend appears to work the other way. The status note says it requires a local build of LLVM, using some of its libraries and executables, and that LLVM is large and slow to build. Textual IR would remove most of that burden.

**Advantages**

- **No link-time dependency.** The compiler just writes text. You need LLVM (`clang` or `llc`/`opt`) only to turn that text into object code, and you can install it as a normal system package.
- **Version tolerance.** The C++ API changes constantly, while textual IR changes more slowly, though it isn't frozen. Typed-pointer IR was replaced by opaque pointers, for example, so you still need to target a specific IR dialect.
- **Debuggability.** You can read, diff and hand-edit the output, run `opt` and `llc` on it separately, and bisect a miscompile by stage. This helps a lot given how subtle backend bugs can be.
- **Smaller and simpler.** Emitting text from the M3CG calls can be a few thousand lines of Modula-3, in the same style as a C backend. This fits your "cleaner and smaller" goal.
- **Fits the existing design.** The code generator is already an object that receives calls, so an IR printer is just another implementation of it.

**Costs and risks**

- **Compile-time overhead.** Printing IR and reparsing it is slower than building it in memory, and invoking external tools adds process overhead. The 2017 note already says the LLVM path compiles noticeably slower than m3cc, so this would likely make it a bit worse. A mitigation is feeding IR to `clang` in one step instead of through separate tools.
- **No programmatic validation.** The in-memory API lets you check the module as you build. With text you only find malformed IR when the tools reject it, with sometimes cryptic errors. A small verifier pass (`opt -verify`) in your test suite helps.
- **Debug info is verbose.** DWARF metadata as text is fiddly and easy to get subtly wrong, though that's equally true through the API.
- **GC integration.** If you later want precise collection through LLVM's statepoint mechanism, you can still express it in textual IR, but it's more cumbersome than through the API. With conservative scanning it's a non-issue.
- **Tooling must be present at build time.** Users need LLVM tools installed to compile Modula-3, though that's no worse than needing a C compiler today.

**How I'd structure it**

1. Write an `LLVMIR`-style code generator that implements the M3CG interface and prints text, keeping a thin internal layer for types and values so the printing logic is separate from the lowering logic.
2. Pin a minimum LLVM version and test against two or three versions in CI, to catch IR dialect drift early.
3. Drive the tools through one wrapper so you can switch from `llc` plus a linker to `clang` as the driver.
4. Keep the runtime in Modula-3 and C, compiled the same way, so the toolchain is uniform.

If the existing backend is salvageable, you could even keep its lowering logic and replace its LLVM API calls with a text printer. That might be the fastest path to a working Phase 1. I haven't read that code, so I can't say how cleanly the lowering and the API calls are separated.

---

## 5. Getting Modula-3 running on 64-bit Linux today

**Question:**

> That sounds like a good plan. Can you research wat is necessary to get M3 running on 64 bit Linux today?

**Answer:**

cm3 d5.11.4 builds and runs on 64-bit Linux. I did the install myself in this sandbox (Ubuntu 24.04, x86_64, GCC 13.3, CMake 3.28, Python 3.13) rather than relying only on the docs.

**What you need**

- **Required tools:** Python 3, CMake, and a C++ compiler. On Debian-family systems the Linux page gives `sudo apt-get install build-essential cmake python3`, and it also lists commands for Arch, Fedora and Gentoo.
- **Optional UI (Trestle):** `xorg-dev` and `libglu1-mesa-dev` on Debian-derived systems. The default install doesn't build the UI. I did not test the UI build.

**Steps** (each copied from the wiki and run as written, apart from my own paths):

```
curl -LO https://github.com/modula3/cm3/releases/download/d5.11.4/cm3-dist-AMD64_LINUX-d5.11.4.tar.xz
tar xf cm3-dist-AMD64_LINUX-d5.11.4.tar.xz
mkdir build && cd build
../cm3-dist-AMD64_LINUX-d5.11.4/scripts/concierge.py install --prefix $HOME/cm3
PATH=$HOME/cm3/bin:$PATH
```

The installer builds a C++ bootstrap compiler, uses it to build the full compiler, then uses that to build and install the bundled libraries. To include the UI, add `all` to the command. If cm3 misdetects your platform, add `--target`, for example `--target ARM64_LINUX`. The AMD64_LINUX download works on x86_64 and aarch64 Linux, and on x86_64 macOS.

**What I observed**

- **Time and size:** It took roughly ten minutes and installed about 223 MB.
- **Result:** `cm3 -version` reports d5.11.4 with host and target AMD64_LINUX. A test program using `libm3` compiled, linked and ran.
- **Type sizes:** The program printed INTEGER 64 bits, LONGINT 64, ADDRESS 64, `Word.Size` 64, and WIDECHAR 16. That confirms two earlier points: INTEGER is word-sized on 64-bit Linux, and WIDECHAR defaults to 16 bits.
- **Noise:** The log has repeated "fatal: not a git repository" messages (the build tries to read git info, which is harmless in a tarball) and about 120 warnings. I found no real errors.
- **Minimal project:** A tiny project needs `src/Main.m3` plus an `m3makefile` containing `import("libm3") implementation("Main") program("hello")`. Running `cm3` in the project root builds into `AMD64_LINUX/`.

**Relevant to your LLVM plan.** All 190 build invocations in the install log ran with `M3_BACKEND_MODE=C`. So this distribution's default path appears to be a C-emitting backend followed by the system C compiler, not the older gcc-based m3cc. That is my reading of the log, not something I confirmed in the build scripts. It means a text-emitting LLVM backend would sit alongside an existing text-emitting backend, and that's useful as a template.

**Caveats**

- I couldn't open the GitHub releases page from here, so I don't know whether anything newer than d5.11.4 exists. The wiki page I read was last edited in January 2022, though the repository itself shows a push as recent as January 2026.
- The wiki's UI command uses the directory `cm3-d5.11.4`, which doesn't match the extracted directory `cm3-dist-AMD64_LINUX-d5.11.4`, so adjust the path.
- Only the base install is verified. The UI libraries, threading under load, and the compiler test suite are untested.

I left the build in my sandbox. I can next try the `all` target with X11 headers, run the `m3tests` suite, or look at how `M3_BACKEND_MODE=C` is wired up in the sources.

Sources:

- [cm3 wiki: Getting Started](https://github.com/modula3/cm3/wiki/Getting-Started)
- [cm3 wiki: Getting Started: Linux (mirror)](https://1clonegithubbyxjn.1934672944.workers.dev/modula3/cm3/wiki/Getting-Started%3A-Linux)
- [cm3 release d5.11.4](https://github.com/modula3/cm3/releases/tag/d5.11.4)
