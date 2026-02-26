OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

/* Restore essential search dirs if you want -lGL without -L */
SEARCH_DIR("=/lib/x86_64-linux-gnu");
SEARCH_DIR("=/usr/lib/x86_64-linux-gnu");
SEARCH_DIR("=/lib64");
SEARCH_DIR("=/usr/lib64");
SEARCH_DIR("=/lib");
SEARCH_DIR("=/usr/lib");

PHDRS
{
  interp  PT_INTERP FLAGS(4);            /* R */
  text    PT_LOAD   FILEHDR PHDRS FLAGS(7); /* R|W|X  (your requirement) */
  data    PT_LOAD   FLAGS(6);            /* R|W */
  dynamic PT_DYNAMIC FLAGS(6);           /* R|W */
}

SECTIONS
{
  . = 0x400000 + SIZEOF_HEADERS;

  /* The interpreter path MUST be in PT_INTERP */
  .interp : { *(.interp) } :interp :text

  /* Put "text-ish" into RWX PT_LOAD */
  .hash           : { *(.hash) }                           :text
  .gnu.hash       : { *(.gnu.hash) }                       :text
  .dynsym         : { *(.dynsym) }                         :text
  .dynstr         : { *(.dynstr) }                         :text
  .rela.dyn       : { *(.rela.dyn) }                       :text
  .rela.plt       : { *(.rela.plt) }                       :text
  .plt            : { *(.plt) *(.plt.*) }                  :text
  .init           : { *(.init) }                           :text
  .text           : { *(.text .text.*) }                   :text
  .fini           : { *(.fini) }                           :text
  .rodata         : { *(.rodata .rodata.*) }               :text
  .eh_frame       : { *(.eh_frame) }                       :text
  .eh_frame_hdr   : { *(.eh_frame_hdr) }                   :text

  /* Writable things into RW PT_LOAD */
  .dynamic        : { *(.dynamic) }                        :data :dynamic
  .got            : { *(.got) *(.got.plt) }                :data
  .data           : { *(.data .data.*) }                   :data
  .bss            : { *(.bss .bss.*) *(COMMON) }           :data
}

