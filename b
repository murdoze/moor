rm mur.o
as mur.asm --defsym ORG=0 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moor

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moord

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 --defsym TRACE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moordt

# ld -r -b binary -o source.o q.moor
# https://www.burtonini.com/blog/2007/07/13/embedding-binary-blobs-with-gcc/
# objcopy --redefine-sym old_name=new_name input_file output_file
