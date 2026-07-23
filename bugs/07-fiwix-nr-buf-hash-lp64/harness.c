/* Minimal harness lifting the EXACT buffer-hash expressions from
   Fiwix 1.5.0 (fs/buffer.c + mm/memory.c), runnable in user space.

     fs/buffer.c:39  #define BUFFER_HASH(dev, block) (((__dev_t)(dev) ^ (__blk_t)(block)) % (NR_BUF_HASH))
     fs/buffer.c:40  #define NR_BUF_HASH (buffer_hash_table_size / sizeof(unsigned int))
     fs/buffer.c:48  struct buffer **buffer_hash_table;
     mm/memory.c:358   pages = ((n * sizeof(unsigned int)) / PAGE_SIZE) + 1;
     mm/memory.c:359   buffer_hash_table_size = pages << PAGE_SHIFT;
     mm/memory.c:363   buffer_hash_table = (struct buffer **)_last_data_addr;
     mm/memory.c:364   _last_data_addr += buffer_hash_table_size;

   The table is an array of `struct buffer *` slots, but BOTH the sizing and
   the index range NR_BUF_HASH are computed in units of sizeof(unsigned int).
   On ILP32 (i386, Fiwix's home target) sizeof(unsigned int) ==
   sizeof(struct buffer *) == 4 and everything lines up.  On LP64,
   sizeof(struct buffer *) == 8, so the hash index range is TWICE the number
   of pointer slots that fit in the allocation: indices [size/8, size/4) are
   out of bounds.

   Build 64-bit with -fsanitize=address: the final write is a loud
   heap-buffer-overflow.  Build with -m32 (control): everything is in bounds
   and the program exits 0.  */
#include <stdio.h>
#include <stdlib.h>

#define PAGE_SHIFT 0x0C          /* include/fiwix/mm.h */
#define PAGE_SIZE (1 << PAGE_SHIFT)

struct buffer;                                   /* slots are struct buffer * */
static unsigned int buffer_hash_table_size = 0;  /* bytes; mm/memory.c */
static struct buffer **buffer_hash_table;

#define NR_BUF_HASH (buffer_hash_table_size / sizeof(unsigned int))  /* fs/buffer.c:40 */

int
main (void)
{
  unsigned int n, pages;

  /* mm_init sizing, verbatim shapes (n = desired number of hashes) */
  n = 1000;
  pages = ((n * sizeof (unsigned int)) / PAGE_SIZE) + 1;   /* mm/memory.c:358 */
  buffer_hash_table_size = pages << PAGE_SHIFT;            /* mm/memory.c:359 */
  /* stand-in for the reserved kernel region of exactly that many bytes */
  buffer_hash_table = (struct buffer **) malloc (buffer_hash_table_size);

  size_t slots_that_fit = buffer_hash_table_size / sizeof (struct buffer *);
  size_t max_index = NR_BUF_HASH - 1;   /* BUFFER_HASH() % NR_BUF_HASH */

  printf ("sizeof(unsigned int)      = %zu\n", sizeof (unsigned int));
  printf ("sizeof(struct buffer *)   = %zu\n", sizeof (struct buffer *));
  printf ("buffer_hash_table_size    = %u bytes\n", buffer_hash_table_size);
  printf ("pointer slots that fit    = %zu\n", slots_that_fit);
  printf ("NR_BUF_HASH (index range) = %zu\n", (size_t) NR_BUF_HASH);
  printf ("highest index used        = %zu\n", max_index);

  if (max_index >= slots_that_fit)
    {
      /* every index in [slots_that_fit, NR_BUF_HASH) is out of bounds */
      size_t first_oob = slots_that_fit;
      printf ("OUT OF BOUNDS: indices %zu..%zu reach byte offsets %zu..%zu in "
              "a %u-byte allocation\n",
              first_oob, max_index,
              first_oob * sizeof (struct buffer *),
              max_index * sizeof (struct buffer *),
              buffer_hash_table_size);
      printf ("performing the exact write getblk/insert does for hash index "
              "%zu: buffer_hash_table[%zu] = ...\n", first_oob, first_oob);
      fflush (stdout);
      buffer_hash_table[first_oob] = 0;   /* ASan: heap-buffer-overflow */
      return 42;                          /* OOB proven arithmetically (no ASan) */
    }

  printf ("in bounds: NR_BUF_HASH == slot count (ILP32 behavior)\n");
  return 0;
}
