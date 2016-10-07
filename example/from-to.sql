INSERT INTO myTable VALUES ("a","01","A","5.59","alice","3");
DELETE FROM myTable WHERE char="a" AND num="16" AND letter="A" LIMIT 1;
DELETE FROM myTable WHERE char="b" AND num="38" AND letter="B" LIMIT 1;
UPDATE myTable SET name="johnny", age="12" WHERE char="b" AND num="38" AND letter="C" LIMIT 1;
