#!/usr/bin/env python3
"""Add the three absolute RISC-V relocations to tinycc's riscv64 linker.

This is the CONTROL leg of the reproducer: the same ~20 lines that turn the
failing/silent link into a working one.  Every edit is asserted -- a scripted
edit that matches nothing otherwise succeeds silently and the "control" would
then be indistinguishable from the buggy build.

Usage: apply-abs-relocs.py <path-to-riscv64-link.c>
"""
import sys

CLASSIFIER_ANCHOR = (
    "    case R_RISCV_PCREL_LO12_S:\n"
    "    case R_RISCV_32_PCREL:\n"
)
CLASSIFIER_NEW = (
    "    case R_RISCV_PCREL_LO12_S:\n"
    "    case R_RISCV_HI20:\n"
    "    case R_RISCV_LO12_I:\n"
    "    case R_RISCV_LO12_S:\n"
    "    case R_RISCV_32_PCREL:\n"
)

RELOCATE_ANCHOR = "    default:\n"
RELOCATE_NEW = """    case R_RISCV_HI20:
        /* absolute lui: imm[31:12] = (S + A + 0x800) >> 12 */
        off64 = (int64_t)(val + 0x800) >> 12;
        if ((off64 + ((uint64_t)1 << 20)) >> 21)
          @ERRFN@("R_RISCV_HI20 relocation failed: off=%lx", (long)off64);
        write32le(ptr, (read32le(ptr) & 0xfff) | ((off64 & 0xfffff) << 12));
        return;
    case R_RISCV_LO12_I:
        write32le(ptr, (read32le(ptr) & 0xfffff) | ((val & 0xfff) << 20));
        return;
    case R_RISCV_LO12_S:
        write32le(ptr, (read32le(ptr) & ~0xfe000f80)
                       | ((val & 0xfe0) << 20) | ((val & 0x1f) << 7));
        return;
"""


def die(msg):
    sys.stderr.write("FATAL: apply-abs-relocs.py: %s\n" % msg)
    sys.exit(1)


def main():
    path = sys.argv[1]
    src = open(path).read()

    if "case R_RISCV_HI20" in src:
        die("%s ALREADY handles R_RISCV_HI20 -- upstream has fixed this; the "
            "reproducer's premise no longer holds" % path)

    # 1. code_reloc() and gotplt_entry_type(): classify the three absolute
    #    forms exactly like their PC-relative siblings.  Exactly two sites.
    n = src.count(CLASSIFIER_ANCHOR)
    if n != 2:
        die("classifier anchor found %d times, expected 2" % n)
    src = src.replace(CLASSIFIER_ANCHOR, CLASSIFIER_NEW)

    # 2. relocate(): the actual field encodings, inserted immediately before
    #    the "default: FIXME: handle reloc type" branch -- the sole "default:"
    #    in the file, and the branch these three currently fall into.
    n = src.count(RELOCATE_ANCHOR)
    if n != 1:
        die("relocate() anchor found %d times, expected 1" % n)
    if "FIXME: handle reloc type" not in src.split(RELOCATE_ANCHOR)[1][:200]:
        die("the sole 'default:' is not the FIXME fall-through branch")

    # relocate()'s out-of-range diagnostic is spelled tcc_error() in the
    # chain-vintage 0.9.26-1157 tree and tcc_error_noabort() on current mob
    # (mob poisons tcc_error inside relocate()).  Follow whatever the
    # neighbouring R_RISCV_PCREL_HI20 range check uses.
    if "tcc_error_noabort(\"R_RISCV_PCREL_HI20 relocation failed" in src:
        errfn = "tcc_error_noabort"
    elif "tcc_error(\"R_RISCV_PCREL_HI20 relocation failed" in src:
        errfn = "tcc_error"
    else:
        die("could not find the R_RISCV_PCREL_HI20 range check to copy the "
            "error-reporting idiom from")
    relocate_new = RELOCATE_NEW.replace("@ERRFN@", errfn)
    print("apply-abs-relocs.py: range-check diagnostic uses %s()" % errfn)
    src = src.replace(RELOCATE_ANCHOR, relocate_new + RELOCATE_ANCHOR)

    for tok in ("case R_RISCV_HI20:", "case R_RISCV_LO12_I:",
                "case R_RISCV_LO12_S:"):
        if src.count(tok) != 3:      # 2 classifiers + 1 relocate
            die("post-condition failed: %s appears %d times, expected 3"
                % (tok, src.count(tok)))

    open(path, "w").write(src)
    print("apply-abs-relocs.py: patched %s (3 relocations x 3 sites)" % path)


main()
