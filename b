rm mur.o
as mur.asm --defsym ORG=0 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moor

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moord

rm mur.o
as mur.asm --defsym ORG=0 --defsym TRACE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moort

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 --defsym TRACE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moordt

rm mur.o
as mur.asm --defsym ORG=0 --defsym BOOT_SOURCE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moors

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 --defsym BOOT_SOURCE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moorsd

rm mur.o
as mur.asm --defsym ORG=0 --defsym TRACE=1 --defsym BOOT_SOURCE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moorst

rm mur.o
as mur.asm --defsym ORG=0 --defsym TRACE=1 --defsym BOOT_SOURCE=1 --defsym DYNAMIC=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld -T mur.ld mur.o -o mur --dynamic-linker=/lib64/ld-linux-x86-64.so.2 -L/lib/x86_64-linux-gnu -L/usr/lib/x86_64-linux-gnu -lc -lGL
mv mur moorlst

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 --defsym TRACE=1 --defsym BOOT_SOURCE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moorsdt

rm mur.o
as mur.asm --defsym SCORCH=1 --defsym ORG=0 --defsym TRACE=1 --defsym BOOT_SOURCE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moorscorch

# ld -r -b binary -o source.o q.moor
# https://www.burtonini.com/blog/2007/07/13/embedding-binary-blobs-with-gcc/
# objcopy --redefine-sym old_name=new_name input_file output_file
