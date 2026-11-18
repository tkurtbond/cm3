# M3CG operation checklist for the LlvmIR backend

Generated from `m3-sys/m3middle/src/M3CG_Ops.i3` by `gen_m3cg_checklist.py`; the Status column is
maintained by hand. Line links point at the implementing procedure in
each reference backend (`—` means no procedure of that name was found,
which usually means the method is inherited or bound under another
name, so check by hand).

Status values: `todo`, `wip`, `done` (implemented and covered by a
test), `n/a` (deliberately not needed; say why in Notes).


## ID counters

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `next_label` | [41](../m3-sys/m3middle/src/M3CG_Ops.i3#L41) | — | [1418](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1418) | done |  |

## READONLY configuration

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `set_error_handler` | [46](../m3-sys/m3middle/src/M3CG_Ops.i3#L46) | [3120](../m3-sys/m3back/src/M3C.m3#L3120) | [1427](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1427) | done |  |

## compilation units

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `begin_unit` | [55](../m3-sys/m3middle/src/M3CG_Ops.i3#L55) | [3208](../m3-sys/m3back/src/M3C.m3#L3208) | [1435](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1435) | done |  |
| `end_unit` | [58](../m3-sys/m3middle/src/M3CG_Ops.i3#L58) | [3217](../m3-sys/m3back/src/M3C.m3#L3217) | [1473](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1473) | done |  |
| `import_unit` | [62](../m3-sys/m3middle/src/M3CG_Ops.i3#L62) | — | [1521](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1521) | done |  |
| `export_unit` | [63](../m3-sys/m3middle/src/M3CG_Ops.i3#L63) | — | [1526](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1526) | done |  |

## debugging line numbers

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `set_source_file` | [68](../m3-sys/m3middle/src/M3CG_Ops.i3#L68) | [3233](../m3-sys/m3back/src/M3C.m3#L3233) | [1533](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1533) | done | Used for source_filename. |
| `set_source_line` | [69](../m3-sys/m3middle/src/M3CG_Ops.i3#L69) | [3249](../m3-sys/m3back/src/M3C.m3#L3249) | [1552](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1552) | done | `!dbg` `DILocation` on each instruction (Phase 5). |

## debugging type declarations

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `declare_typename` | [83](../m3-sys/m3middle/src/M3CG_Ops.i3#L83) | [3330](../m3-sys/m3back/src/M3C.m3#L3330) | [1578](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1578) | done | Debug info: names the DI type (Phase 5, `M3LLVMIRDebug`). |
| `declare_array` | [89](../m3-sys/m3middle/src/M3CG_Ops.i3#L89) | [3349](../m3-sys/m3back/src/M3C.m3#L3349) | [1609](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1609) | done | Debug info: `DW_TAG_array_type` with a `DISubrange` (Phase 5). |
| `declare_open_array` | [91](../m3-sys/m3middle/src/M3CG_Ops.i3#L91) | [3364](../m3-sys/m3back/src/M3C.m3#L3364) | [1619](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1619) | done | Debug info: array with `dataLocation`/`upperBound` expressions over the dope vector (Phase 5). |
| `declare_enum` | [94](../m3-sys/m3middle/src/M3CG_Ops.i3#L94) | [3408](../m3-sys/m3back/src/M3C.m3#L3408) | [1629](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1629) | done | Debug info: `DW_TAG_enumeration_type` with an unsigned base type (Phase 5). |
| `declare_enum_elt` | [98](../m3-sys/m3middle/src/M3CG_Ops.i3#L98) | [3444](../m3-sys/m3back/src/M3C.m3#L3444) | [1640](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1640) | done | Debug info: `DIEnumerator` (Phase 5). |
| `declare_packed` | [101](../m3-sys/m3middle/src/M3CG_Ops.i3#L101) | [3482](../m3-sys/m3back/src/M3C.m3#L3482) | [1649](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1649) | done | Debug info: the base type; packed fields become bit fields (Phase 5). |
| `declare_record` | [103](../m3-sys/m3middle/src/M3CG_Ops.i3#L103) | [3592](../m3-sys/m3back/src/M3C.m3#L3592) | [1659](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1659) | done | Debug info: `DW_TAG_structure_type`; typeid -1 records describe the module's globals (Phase 5). |
| `declare_field` | [108](../m3-sys/m3middle/src/M3CG_Ops.i3#L108) | [3625](../m3-sys/m3back/src/M3C.m3#L3625) | [1678](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1678) | done | Debug info: `DW_TAG_member`, `DIFlagBitField` when not byte-aligned (Phase 5). |
| `declare_set` | [111](../m3-sys/m3middle/src/M3CG_Ops.i3#L111) | [3666](../m3-sys/m3back/src/M3C.m3#L3666) | [1696](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1696) | done | Debug info: `DW_TAG_set_type` over enums and subranges (Phase 5). |
| `declare_subrange` | [113](../m3-sys/m3middle/src/M3CG_Ops.i3#L113) | [3718](../m3-sys/m3back/src/M3C.m3#L3718) | [1706](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1706) | done | Debug info: `DW_TAG_subrange_type`; unsigned when min >= 0 (Phase 5). |
| `declare_pointer` | [115](../m3-sys/m3middle/src/M3CG_Ops.i3#L115) | [3778](../m3-sys/m3back/src/M3C.m3#L3778) | [1725](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1725) | done | Debug info: `DW_TAG_pointer_type` (Phase 5). |
| `declare_indirect` | [118](../m3-sys/m3middle/src/M3CG_Ops.i3#L118) | [3795](../m3-sys/m3back/src/M3C.m3#L3795) | [1738](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1738) | done | Debug info: VAR/large parameters get `DW_OP_deref` (Phase 5). |
| `declare_proctype` | [121](../m3-sys/m3middle/src/M3CG_Ops.i3#L121) | [3819](../m3-sys/m3back/src/M3C.m3#L3819) | [1747](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1747) | done | Debug info: pointer to a `DISubroutineType` (Phase 5). |
| `declare_formal` | [130](../m3-sys/m3middle/src/M3CG_Ops.i3#L130) | [3848](../m3-sys/m3back/src/M3C.m3#L3848) | [1770](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1770) | done | Debug info: a parameter type of the `DISubroutineType` (Phase 5). |
| `declare_raises` | [134](../m3-sys/m3middle/src/M3CG_Ops.i3#L134) | [3870](../m3-sys/m3back/src/M3C.m3#L3870) | [1781](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1781) | done | No-op: RAISES isn't described in DWARF. |
| `declare_object` | [138](../m3-sys/m3middle/src/M3CG_Ops.i3#L138) | [3884](../m3-sys/m3back/src/M3C.m3#L3884) | [1790](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1790) | done | Debug info: pointer to a class struct with `DW_TAG_inheritance` and a `_methods` member (Phase 5). |
| `declare_method` | [149](../m3-sys/m3middle/src/M3CG_Ops.i3#L149) | [3931](../m3-sys/m3back/src/M3C.m3#L3931) | [1828](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1828) | done | Debug info: a member of the object's method-suite struct, `_methods` (Phase 5). |
| `declare_opaque` | [152](../m3-sys/m3middle/src/M3CG_Ops.i3#L152) | [3943](../m3-sys/m3back/src/M3C.m3#L3943) | [1838](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1838) | done | Debug info: an opaque type, resolved through `reveal_opaque` (Phase 5). |
| `reveal_opaque` | [157](../m3-sys/m3middle/src/M3CG_Ops.i3#L157) | [3956](../m3-sys/m3back/src/M3C.m3#L3956) | [1852](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1852) | done | Debug info: maps the opaque type to its revelation (Phase 5). |
| `declare_exception` | [160](../m3-sys/m3middle/src/M3CG_Ops.i3#L160) | [3972](../m3-sys/m3back/src/M3C.m3#L3972) | [1872](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1872) | done | No-op: exceptions aren't described. |
| `widechar_size` | [168](../m3-sys/m3middle/src/M3CG_Ops.i3#L168) | — | [1885](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1885) | done | Debug info: the size of WIDECHAR (Phase 5). |

## runtime hooks

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `set_runtime_proc` | [175](../m3-sys/m3middle/src/M3CG_Ops.i3#L175) | [4018](../m3-sys/m3back/src/M3C.m3#L4018) | [1916](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1916) | done | No-op. |

## variable declarations

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `import_global` | [208](../m3-sys/m3middle/src/M3CG_Ops.i3#L208) | [4030](../m3-sys/m3back/src/M3C.m3#L4030) | [1933](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1933) | done |  |
| `declare_segment` | [213](../m3-sys/m3middle/src/M3CG_Ops.i3#L213) | [4074](../m3-sys/m3back/src/M3C.m3#L4074) | [1958](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1958) | done |  |
| `bind_segment` | [214](../m3-sys/m3middle/src/M3CG_Ops.i3#L214) | [4110](../m3-sys/m3back/src/M3C.m3#L4110) | [1992](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L1992) | done | Debug info: `DIGlobalVariableExpression`s for the module's globals (Phase 5). |
| `declare_global` | [222](../m3-sys/m3middle/src/M3CG_Ops.i3#L222) | [4135](../m3-sys/m3back/src/M3C.m3#L4135) | [2007](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2007) | done |  |
| `declare_constant` | [229](../m3-sys/m3middle/src/M3CG_Ops.i3#L229) | [4162](../m3-sys/m3back/src/M3C.m3#L4162) | [2045](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2045) | done |  |
| `declare_local` | [235](../m3-sys/m3middle/src/M3CG_Ops.i3#L235) | [5362](../m3-sys/m3back/src/M3C.m3#L5362) | [2098](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2098) | done | Up-level locals live in the `%frame` block (offset 8 on; offset 0 is the static link). Named locals get a `DILocalVariable` and `llvm.dbg.declare` (Phase 5). |
| `declare_param` | [258](../m3-sys/m3middle/src/M3CG_Ops.i3#L258) | [4986](../m3-sys/m3back/src/M3C.m3#L4986) | [2157](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2157) | done | Struct params arrive as `ptr` and are copied into a local; up-level params are copied into `%frame`. Parameters get a `DILocalVariable` with `arg:` (Phase 5). |
| `declare_temp` | [273](../m3-sys/m3middle/src/M3CG_Ops.i3#L273) | [5599](../m3-sys/m3back/src/M3C.m3#L5599) | [2197](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2197) | done |  |
| `free_temp` | [279](../m3-sys/m3middle/src/M3CG_Ops.i3#L279) | [5611](../m3-sys/m3back/src/M3C.m3#L5611) | [2215](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2215) | done | No-op. |

## static variable initialization

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `begin_init` | [293](../m3-sys/m3middle/src/M3CG_Ops.i3#L293) | [5618](../m3-sys/m3back/src/M3C.m3#L5618) | [2228](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2228) | done |  |
| `end_init` | [294](../m3-sys/m3middle/src/M3CG_Ops.i3#L294) | [5643](../m3-sys/m3back/src/M3C.m3#L5643) | [2237](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2237) | done |  |
| `init_int` | [297](../m3-sys/m3middle/src/M3CG_Ops.i3#L297) | [5776](../m3-sys/m3back/src/M3C.m3#L5776) | [2369](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2369) | done |  |
| `init_proc` | [301](../m3-sys/m3middle/src/M3CG_Ops.i3#L301) | [5803](../m3-sys/m3back/src/M3C.m3#L5803) | [2379](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2379) | done |  |
| `init_label` | [305](../m3-sys/m3middle/src/M3CG_Ops.i3#L305) | [5839](../m3-sys/m3back/src/M3C.m3#L5839) | [2388](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2388) | done | Phase 3: no-op, as in M3C and M3CG_LLVM (only the old stack walker reads these words); not emitted for AMD64_LINUX m3tests. |
| `init_var` | [309](../m3-sys/m3middle/src/M3CG_Ops.i3#L309) | [5851](../m3-sys/m3back/src/M3C.m3#L5851) | [2398](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2398) | done |  |
| `init_offset` | [314](../m3-sys/m3middle/src/M3CG_Ops.i3#L314) | [5872](../m3-sys/m3back/src/M3C.m3#L5872) | [2407](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2407) | done | Phase 3: no-op, as in M3C and M3CG_LLVM (only the old stack walker reads these words); not emitted for AMD64_LINUX m3tests. |
| `init_chars` | [319](../m3-sys/m3middle/src/M3CG_Ops.i3#L319) | [5887](../m3-sys/m3back/src/M3C.m3#L5887) | [2418](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2418) | done |  |
| `init_float` | [323](../m3-sys/m3middle/src/M3CG_Ops.i3#L323) | [6040](../m3-sys/m3back/src/M3C.m3#L6040) | [2427](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2427) | done |  |

## procedures

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `import_procedure` | [350](../m3-sys/m3middle/src/M3CG_Ops.i3#L350) | [6061](../m3-sys/m3back/src/M3C.m3#L6061) | [2445](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2445) | done |  |
| `declare_procedure` | [361](../m3-sys/m3middle/src/M3CG_Ops.i3#L361) | [6111](../m3-sys/m3back/src/M3C.m3#L6111) | [2493](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2493) | done | Nested procedures take the static link as a trailing `ptr %sl` parameter. |
| `begin_procedure` | [376](../m3-sys/m3middle/src/M3CG_Ops.i3#L376) | [6213](../m3-sys/m3back/src/M3C.m3#L6213) | [2521](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2521) | done | Debug info: the `DISubprogram` (Phase 5). |
| `end_procedure` | [380](../m3-sys/m3middle/src/M3CG_Ops.i3#L380) | [6342](../m3-sys/m3back/src/M3C.m3#L6342) | [2698](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2698) | done |  |
| `begin_block` | [384](../m3-sys/m3middle/src/M3CG_Ops.i3#L384) | [6355](../m3-sys/m3back/src/M3C.m3#L6355) | [2774](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2774) | done | Opens a `DILexicalBlock` for the block's locals and code (Phase 5). |
| `end_block` | [385](../m3-sys/m3middle/src/M3CG_Ops.i3#L385) | [6364](../m3-sys/m3back/src/M3C.m3#L6364) | [2780](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2780) | done | Closes the `DILexicalBlock`. |
| `note_procedure_origin` | [388](../m3-sys/m3middle/src/M3CG_Ops.i3#L388) | [6373](../m3-sys/m3back/src/M3C.m3#L6373) | [2786](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2786) | done | No-op. |

## statements

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `set_label` | [397](../m3-sys/m3middle/src/M3CG_Ops.i3#L397) | [6380](../m3-sys/m3back/src/M3C.m3#L6380) | [2818](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2818) | done |  |
| `jump` | [401](../m3-sys/m3middle/src/M3CG_Ops.i3#L401) | [6393](../m3-sys/m3back/src/M3C.m3#L6393) | [2867](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2867) | done |  |
| `if_true` | [404](../m3-sys/m3middle/src/M3CG_Ops.i3#L404) | [6416](../m3-sys/m3back/src/M3C.m3#L6416) | [2934](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2934) | done |  |
| `if_false` | [407](../m3-sys/m3middle/src/M3CG_Ops.i3#L407) | [6422](../m3-sys/m3back/src/M3C.m3#L6422) | [2940](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2940) | done |  |
| `if_compare` | [410](../m3-sys/m3middle/src/M3CG_Ops.i3#L410) | [6448](../m3-sys/m3back/src/M3C.m3#L6448) | [2946](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2946) | done |  |
| `case_jump` | [413](../m3-sys/m3middle/src/M3CG_Ops.i3#L413) | [6464](../m3-sys/m3back/src/M3C.m3#L6464) | [2982](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L2982) | done |  |
| `exit_proc` | [416](../m3-sys/m3middle/src/M3CG_Ops.i3#L416) | [6480](../m3-sys/m3back/src/M3C.m3#L6480) | [3009](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3009) | done |  |

## load/store

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `load` | [431](../m3-sys/m3middle/src/M3CG_Ops.i3#L431) | [6594](../m3-sys/m3back/src/M3C.m3#L6594) | [3148](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3148) | done |  |
| `load_address` | [437](../m3-sys/m3middle/src/M3CG_Ops.i3#L437) | [6656](../m3-sys/m3back/src/M3C.m3#L6656) | [3223](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3223) | done |  |
| `load_indirect` | [440](../m3-sys/m3middle/src/M3CG_Ops.i3#L440) | [6675](../m3-sys/m3back/src/M3C.m3#L6675) | [3243](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3243) | done |  |
| `store` | [444](../m3-sys/m3middle/src/M3CG_Ops.i3#L444) | [6639](../m3-sys/m3back/src/M3C.m3#L6639) | [3181](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3181) | done |  |
| `store_indirect` | [447](../m3-sys/m3middle/src/M3CG_Ops.i3#L447) | [6701](../m3-sys/m3back/src/M3C.m3#L6701) | [3265](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3265) | done |  |

## literals

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `load_nil` | [485](../m3-sys/m3middle/src/M3CG_Ops.i3#L485) | [6721](../m3-sys/m3back/src/M3C.m3#L6721) | [3292](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3292) | done |  |
| `load_integer` | [486](../m3-sys/m3middle/src/M3CG_Ops.i3#L486) | [6760](../m3-sys/m3back/src/M3C.m3#L6760) | [3300](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3300) | done |  |
| `load_float` | [487](../m3-sys/m3middle/src/M3CG_Ops.i3#L487) | [6786](../m3-sys/m3back/src/M3C.m3#L6786) | [3368](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3368) | done |  |

## arithmetic

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `compare` | [495](../m3-sys/m3middle/src/M3CG_Ops.i3#L495) | [6938](../m3-sys/m3back/src/M3C.m3#L6938) | [3485](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3485) | done |  |
| `add` | [496](../m3-sys/m3middle/src/M3CG_Ops.i3#L496) | [6963](../m3-sys/m3back/src/M3C.m3#L6963) | [3509](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3509) | done |  |
| `subtract` | [497](../m3-sys/m3middle/src/M3CG_Ops.i3#L497) | [6970](../m3-sys/m3back/src/M3C.m3#L6970) | [3515](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3515) | done |  |
| `multiply` | [498](../m3-sys/m3middle/src/M3CG_Ops.i3#L498) | [6976](../m3-sys/m3back/src/M3C.m3#L6976) | [3521](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3521) | done |  |
| `divide` | [499](../m3-sys/m3middle/src/M3CG_Ops.i3#L499) | [6982](../m3-sys/m3back/src/M3C.m3#L6982) | [3527](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3527) | done |  |
| `negate` | [500](../m3-sys/m3middle/src/M3CG_Ops.i3#L500) | [7020](../m3-sys/m3back/src/M3C.m3#L7020) | [3533](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3533) | done |  |
| `abs` | [501](../m3-sys/m3middle/src/M3CG_Ops.i3#L501) | [7026](../m3-sys/m3back/src/M3C.m3#L7026) | [3580](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3580) | done |  |
| `max` | [502](../m3-sys/m3middle/src/M3CG_Ops.i3#L502) | [7037](../m3-sys/m3back/src/M3C.m3#L7037) | [3637](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3637) | done |  |
| `min` | [503](../m3-sys/m3middle/src/M3CG_Ops.i3#L503) | [7049](../m3-sys/m3back/src/M3C.m3#L7049) | [3643](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3643) | done |  |
| `cvt_int` | [504](../m3-sys/m3middle/src/M3CG_Ops.i3#L504) | [7061](../m3-sys/m3back/src/M3C.m3#L7061) | [3672](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3672) | done |  |
| `cvt_float` | [505](../m3-sys/m3middle/src/M3CG_Ops.i3#L505) | [7072](../m3-sys/m3back/src/M3C.m3#L7072) | [3686](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3686) | done |  |
| `div` | [506](../m3-sys/m3middle/src/M3CG_Ops.i3#L506) | [6988](../m3-sys/m3back/src/M3C.m3#L6988) | [3802](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3802) | done |  |
| `mod` | [507](../m3-sys/m3middle/src/M3CG_Ops.i3#L507) | [7004](../m3-sys/m3back/src/M3C.m3#L7004) | [3817](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3817) | done |  |

## sets

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `set_union` | [515](../m3-sys/m3middle/src/M3CG_Ops.i3#L515) | [7099](../m3-sys/m3back/src/M3C.m3#L7099) | [3914](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3914) | done |  |
| `set_difference` | [516](../m3-sys/m3middle/src/M3CG_Ops.i3#L516) | [7105](../m3-sys/m3back/src/M3C.m3#L7105) | [3920](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3920) | done |  |
| `set_intersection` | [517](../m3-sys/m3middle/src/M3CG_Ops.i3#L517) | [7111](../m3-sys/m3back/src/M3C.m3#L7111) | [3926](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3926) | done |  |
| `set_sym_difference` | [518](../m3-sys/m3middle/src/M3CG_Ops.i3#L518) | [7117](../m3-sys/m3back/src/M3C.m3#L7117) | [3932](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3932) | done |  |
| `set_member` | [519](../m3-sys/m3middle/src/M3CG_Ops.i3#L519) | [7123](../m3-sys/m3back/src/M3C.m3#L7123) | [3938](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3938) | done |  |
| `set_compare` | [520](../m3-sys/m3middle/src/M3CG_Ops.i3#L520) | [7135](../m3-sys/m3back/src/M3C.m3#L7135) | [3966](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3966) | done |  |
| `set_range` | [521](../m3-sys/m3middle/src/M3CG_Ops.i3#L521) | [7164](../m3-sys/m3back/src/M3C.m3#L7164) | [3986](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3986) | done |  |
| `set_singleton` | [522](../m3-sys/m3middle/src/M3CG_Ops.i3#L522) | [7177](../m3-sys/m3back/src/M3C.m3#L7177) | [3996](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L3996) | done |  |

## Word.T bit operations

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `not` | [526](../m3-sys/m3middle/src/M3CG_Ops.i3#L526) | [7191](../m3-sys/m3back/src/M3C.m3#L7191) | [4008](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4008) | done |  |
| `and` | [527](../m3-sys/m3middle/src/M3CG_Ops.i3#L527) | [7197](../m3-sys/m3back/src/M3C.m3#L7197) | [4019](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4019) | done |  |
| `or` | [528](../m3-sys/m3middle/src/M3CG_Ops.i3#L528) | [7203](../m3-sys/m3back/src/M3C.m3#L7203) | [4024](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4024) | done |  |
| `xor` | [529](../m3-sys/m3middle/src/M3CG_Ops.i3#L529) | [7209](../m3-sys/m3back/src/M3C.m3#L7209) | [4029](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4029) | done |  |
| `shift` | [531](../m3-sys/m3middle/src/M3CG_Ops.i3#L531) | [7278](../m3-sys/m3back/src/M3C.m3#L7278) | [4034](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4034) | done |  |
| `shift_left` | [532](../m3-sys/m3middle/src/M3CG_Ops.i3#L532) | [7249](../m3-sys/m3back/src/M3C.m3#L7249) | [4089](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4089) | done |  |
| `shift_right` | [533](../m3-sys/m3middle/src/M3CG_Ops.i3#L533) | [7259](../m3-sys/m3back/src/M3C.m3#L7259) | [4095](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4095) | done |  |
| `rotate` | [534](../m3-sys/m3middle/src/M3CG_Ops.i3#L534) | [7284](../m3-sys/m3back/src/M3C.m3#L7284) | [4124](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4124) | done |  |
| `rotate_left` | [535](../m3-sys/m3middle/src/M3CG_Ops.i3#L535) | [7290](../m3-sys/m3back/src/M3C.m3#L7290) | [4165](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4165) | done |  |
| `rotate_right` | [536](../m3-sys/m3middle/src/M3CG_Ops.i3#L536) | [7296](../m3-sys/m3back/src/M3C.m3#L7296) | [4182](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4182) | done |  |
| `widen` | [538](../m3-sys/m3middle/src/M3CG_Ops.i3#L538) | [7302](../m3-sys/m3back/src/M3C.m3#L7302) | [4199](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4199) | done |  |
| `chop` | [541](../m3-sys/m3middle/src/M3CG_Ops.i3#L541) | [7309](../m3-sys/m3back/src/M3C.m3#L7309) | [4214](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4214) | done |  |
| `extract` | [544](../m3-sys/m3middle/src/M3CG_Ops.i3#L544) | [7316](../m3-sys/m3back/src/M3C.m3#L7316) | [4246](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4246) | done |  |
| `extract_n` | [548](../m3-sys/m3middle/src/M3CG_Ops.i3#L548) | [7331](../m3-sys/m3back/src/M3C.m3#L7331) | [4276](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4276) | done |  |
| `extract_mn` | [552](../m3-sys/m3middle/src/M3CG_Ops.i3#L552) | [7350](../m3-sys/m3back/src/M3C.m3#L7350) | [4298](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4298) | done |  |
| `insert` | [556](../m3-sys/m3middle/src/M3CG_Ops.i3#L556) | [7366](../m3-sys/m3back/src/M3C.m3#L7366) | [4341](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4341) | done |  |
| `insert_n` | [559](../m3-sys/m3middle/src/M3CG_Ops.i3#L559) | [7380](../m3-sys/m3back/src/M3C.m3#L7380) | [4367](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4367) | done |  |
| `insert_mn` | [562](../m3-sys/m3middle/src/M3CG_Ops.i3#L562) | [7390](../m3-sys/m3back/src/M3C.m3#L7390) | [4393](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4393) | done |  |

## misc. stack/memory ops

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `swap` | [567](../m3-sys/m3middle/src/M3CG_Ops.i3#L567) | [7403](../m3-sys/m3back/src/M3C.m3#L7403) | [4418](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4418) | done |  |
| `pop` | [570](../m3-sys/m3middle/src/M3CG_Ops.i3#L570) | [2796](../m3-sys/m3back/src/M3C.m3#L2796) | [4430](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4430) | done |  |
| `copy_n` | [573](../m3-sys/m3middle/src/M3CG_Ops.i3#L573) | [7427](../m3-sys/m3back/src/M3C.m3#L7427) | [4446](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4446) | done |  |
| `copy` | [578](../m3-sys/m3middle/src/M3CG_Ops.i3#L578) | [7440](../m3-sys/m3back/src/M3C.m3#L7440) | [4469](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4469) | done |  |
| `zero_n` | [583](../m3-sys/m3middle/src/M3CG_Ops.i3#L583) | [7452](../m3-sys/m3back/src/M3C.m3#L7452) | [4493](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4493) | done |  |
| `zero` | [586](../m3-sys/m3middle/src/M3CG_Ops.i3#L586) | [7466](../m3-sys/m3back/src/M3C.m3#L7466) | [4510](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4510) | done |  |

## conversions

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `loophole` | [591](../m3-sys/m3middle/src/M3CG_Ops.i3#L591) | [7479](../m3-sys/m3back/src/M3C.m3#L7479) | [4629](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4629) | done |  |

## traps & runtime checks

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `abort` | [605](../m3-sys/m3middle/src/M3CG_Ops.i3#L605) | [7541](../m3-sys/m3back/src/M3C.m3#L7541) | [4708](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4708) | done |  |
| `check_nil` | [608](../m3-sys/m3middle/src/M3CG_Ops.i3#L608) | [7550](../m3-sys/m3back/src/M3C.m3#L7550) | [4768](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4768) | done |  |
| `check_lo` | [611](../m3-sys/m3middle/src/M3CG_Ops.i3#L611) | [7567](../m3-sys/m3back/src/M3C.m3#L7567) | [4779](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4779) | done |  |
| `check_hi` | [614](../m3-sys/m3middle/src/M3CG_Ops.i3#L614) | [7584](../m3-sys/m3back/src/M3C.m3#L7584) | [4791](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4791) | done |  |
| `check_range` | [617](../m3-sys/m3middle/src/M3CG_Ops.i3#L617) | [7601](../m3-sys/m3back/src/M3C.m3#L7601) | [4803](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4803) | done |  |
| `check_index` | [620](../m3-sys/m3middle/src/M3CG_Ops.i3#L620) | [7616](../m3-sys/m3back/src/M3C.m3#L7616) | [4817](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4817) | done |  |
| `check_eq` | [625](../m3-sys/m3middle/src/M3CG_Ops.i3#L625) | [7648](../m3-sys/m3back/src/M3C.m3#L7648) | [4832](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4832) | done |  |

## address arithmetic

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `add_offset` | [630](../m3-sys/m3middle/src/M3CG_Ops.i3#L630) | [7676](../m3-sys/m3back/src/M3C.m3#L7676) | [4847](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4847) | done |  |
| `index_address` | [633](../m3-sys/m3middle/src/M3CG_Ops.i3#L633) | [7687](../m3-sys/m3back/src/M3C.m3#L7687) | [4858](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4858) | done |  |

## procedure calls

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `start_call_direct` | [664](../m3-sys/m3middle/src/M3CG_Ops.i3#L664) | [7724](../m3-sys/m3back/src/M3C.m3#L7724) | [4876](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4876) | done | Passes the static link last; pads missing declared params with zero (FINALLY handlers, see TryFinStmt). |
| `call_direct` | [669](../m3-sys/m3middle/src/M3CG_Ops.i3#L669) | [7933](../m3-sys/m3back/src/M3C.m3#L7933) | [5061](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5061) | done |  |
| `start_call_indirect` | [672](../m3-sys/m3middle/src/M3CG_Ops.i3#L672) | [7744](../m3-sys/m3back/src/M3C.m3#L7744) | [5121](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5121) | done |  |
| `call_indirect` | [676](../m3-sys/m3middle/src/M3CG_Ops.i3#L676) | [7953](../m3-sys/m3back/src/M3C.m3#L7953) | [5380](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5380) | done |  |
| `start_try` | [680](../m3-sys/m3middle/src/M3CG_Ops.i3#L680) | [8020](../m3-sys/m3back/src/M3C.m3#L8020) | [4907](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4907) | done | Opens a region whose calls become `invoke`s to its landing pad (Phase 7, ex_stack). |
| `end_try` | [683](../m3-sys/m3middle/src/M3CG_Ops.i3#L683) | [8034](../m3-sys/m3back/src/M3C.m3#L8034) | [4912](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L4912) | done | Closes the region; the next `landing_pad` belongs to it. |
| `invoke_direct` | [686](../m3-sys/m3middle/src/M3CG_Ops.i3#L686) | [8051](../m3-sys/m3back/src/M3C.m3#L8051) | [5066](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5066) | done | Checks the handler is the region's, then `call_direct` (which emits the `invoke`). |
| `invoke_indirect` | [691](../m3-sys/m3middle/src/M3CG_Ops.i3#L691) | [8065](../m3-sys/m3back/src/M3C.m3#L8065) | [5385](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5385) | done | As `invoke_direct`, with `call_indirect`. |
| `landing_pad` | [697](../m3-sys/m3middle/src/M3CG_Ops.i3#L697) | [8080](../m3-sys/m3back/src/M3C.m3#L8080) | [5071](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5071) | done | `landingpad` catching `_M3Exc` with `__gxx_personality_v0`; pushes the activation. |
| `pop_param` | [703](../m3-sys/m3middle/src/M3CG_Ops.i3#L703) | [7761](../m3-sys/m3back/src/M3C.m3#L7761) | [5391](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5391) | done |  |
| `pop_struct` | [706](../m3-sys/m3middle/src/M3CG_Ops.i3#L706) | [7774](../m3-sys/m3back/src/M3C.m3#L7774) | [5407](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5407) | done |  |
| `pop_static_link` | [719](../m3-sys/m3middle/src/M3CG_Ops.i3#L719) | [7808](../m3-sys/m3back/src/M3C.m3#L7808) | [5438](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5438) | done |  |

## procedure and closure types

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `load_procedure` | [724](../m3-sys/m3middle/src/M3CG_Ops.i3#L724) | [8097](../m3-sys/m3back/src/M3C.m3#L8097) | [5453](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5453) | done |  |
| `load_static_link` | [727](../m3-sys/m3middle/src/M3CG_Ops.i3#L727) | [8108](../m3-sys/m3back/src/M3C.m3#L8108) | [5465](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5465) | done |  |

## misc.

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `comment` | [732](../m3-sys/m3middle/src/M3CG_Ops.i3#L732) | [8142](../m3-sys/m3back/src/M3C.m3#L8142) | [5498](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5498) | done |  |

## atomics

| Op | Decl | M3C | M3CG_LLVM | Status | Notes |
|---|---|---|---|---|---|
| `store_ordered` | [739](../m3-sys/m3middle/src/M3CG_Ops.i3#L739) | [8165](../m3-sys/m3back/src/M3C.m3#L8165) | [5535](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5535) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
| `load_ordered` | [742](../m3-sys/m3middle/src/M3CG_Ops.i3#L742) | [8177](../m3-sys/m3back/src/M3C.m3#L8177) | [5555](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5555) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
| `exchange` | [745](../m3-sys/m3middle/src/M3CG_Ops.i3#L745) | [8186](../m3-sys/m3back/src/M3C.m3#L8186) | [5579](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5579) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
| `compare_exchange` | [748](../m3-sys/m3middle/src/M3CG_Ops.i3#L748) | [8197](../m3-sys/m3back/src/M3C.m3#L8197) | [5606](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5606) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
| `fence` | [758](../m3-sys/m3middle/src/M3CG_Ops.i3#L758) | [8219](../m3-sys/m3back/src/M3C.m3#L8219) | [5649](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5649) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
| `fetch_and_op` | [761](../m3-sys/m3middle/src/M3CG_Ops.i3#L761) | [8234](../m3-sys/m3back/src/M3C.m3#L8234) | [5662](../m3-sys/llvm/llvm22/src/M3CG_LLVM.m3#L5662) | done | Phase 3: LLVM atomic instructions. Covered by a hand-linked value test (the builtin `Atomic*` interfaces have no exporter while `m3core/src/atomic` is disabled, so p226 cannot link with any backend); p226 IR verifies. M3C leaves most of these as empty stubs. |
