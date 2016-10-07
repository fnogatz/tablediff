# tablediff

Shell scripts to get a minimal set of SQL commands for table synchronisation.

The tablediff repository contains scripts to compare two table dumps given as unsorted CSV files and create a minimal set of SQL commands to go from one to the other. It consists of two parts:
- `diff.sh`, which generates a minimal patch file for the given CSV files based on the specified primary key columns.
- `patch.sh`, which takes a patch file for CSV rows and generates appropriate SQL commands to get from one data version to the other.

## Usage Example

Consider the following two CSV files:

*example/from.csv*
```
a|16|A|5.59|alice|3
b|38|B|3.78|bob|9
b|38|C|0.00|john|10
c|72|D|2.02|carla|8
c|76|D|4.11|paul|8
d|76|D|4.11|jenny|8
```

*example/to.csv*
```
c|76|D|4.11|paul|8
a|01|A|5.59|alice|3
c|72|D|2.02|carla|8
d|76|D|4.11|jenny|8
b|38|C|0.00|johnny|12
```

This could be two dumps of the table `myTable` with the columns `char`, `num`, `letter`, `price`, `name`, `age`, where `(char, num, letter)` form the compound primary key.

### Patch File Generation: `diff.sh`

Using `diff.sh` we can create a minimal patch file for these two CSV files:

```
./diff.sh --empty --delimiter='|' --primary=1,2,3 example/from.csv example/to.csv
1c1
< a|16|A|5.59|alice|3
---
> a|01|A|5.59|alice|3
1,2c1
< b|38|B|3.78|bob|9
< b|38|C|0.00|john|10
---
> b|38|C|0.00|johnny|12
```

Use `./diff.sh --help` to get an overview about all the options. The generated ouput is a standard patch file generated by `diff`.

### SQL Commands Generation: `patch.sh`

The `patch.sh` consumes the patch file and generates the needed `INSERT`, `DELETE` and `UPDATE` statements to get from one data set to the other. It generates a minimal set of SQL commands.

```
./patch.sh --delimiter='|' --primary=1,2,3 myTable char,num,letter,price,name,age < example/from-to.diff 
INSERT INTO myTable VALUES ("a","01","A","5.59","alice","3");
DELETE FROM myTable WHERE char="a" AND num="16" AND letter="A" LIMIT 1;
DELETE FROM myTable WHERE char="b" AND num="38" AND letter="B" LIMIT 1;
UPDATE myTable SET name="johnny", age="12" WHERE char="b" AND num="38" AND letter="C" LIMIT 1;
```

Use `./patch.sh --help` to get an overview about all the options.

## Background

As part of a project at the University of Würzburg we use a MySQL table, where under 1% of all data rows are changed per day. However, only the table's CSV dumps are known for synchronisation. In order to get a minimal set of instructions to go from one data version to the other, `tablediff` was created.

The `diff.sh` uses a combination of shell's `awk`, `sort`, `cmp`, and `diff` commands, to split, sort, and compare large CSV files based on their primary key. As in our example this is a compound primary key with more than two columns, some calls are parallelized, because shell's `sort` can use only two columns.

Some numbers of our initial example at the University of Würzburg:
- two CSV files, each of 830MB and 11m rows
- overall process (`diff.sh` and `patch.sh`) takes 100 seconds on i5, 4x 2.30GHz and takes up to 2.2GB RAM
- generates a 10MB large SQL file with 34'000 instructions, including
  - 5'300 `INSERT`
  - 700 `DELETE`
  - 28'000 `UPDATE`