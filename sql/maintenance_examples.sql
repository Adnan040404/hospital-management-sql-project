-- The two original practice tasks that CHANGE the database (Q7 and Q8).
-- They are kept apart from queries.sql because running them changes the data
-- the other queries read. The tests run them on a throwaway copy.

-- Q7: Correct the name of the patient with id 5
UPDATE patient
SET name = 'Robert', surname = 'Fernandez'
WHERE patient_id = 5;

-- Q8: Drop the phone column
-- (SQLite 3.35+ and MySQL both accept this; on older SQLite you would have to
--  rebuild the table.)
ALTER TABLE patient DROP COLUMN phone;
