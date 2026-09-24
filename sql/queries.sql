-- Queries 1-24 are the original practice set (fixed where noted).
-- Queries 25-33 are new: window functions, CTEs, CASE and NOT EXISTS.
--
-- Every query starts with a "-- Q<number>: <title>" line; run_queries.py uses
-- that line to split the file, so keep the format if you add more.
-- Text is joined with || (SQLite/PostgreSQL). On MySQL, use CONCAT(a, ' ', b).

-- Q1: Physicians in alphabetical order
SELECT name AS physician_name
FROM physician
ORDER BY name;

-- Q2: Full name of male patients
SELECT name || ' ' || surname AS patient_fullname, gender
FROM patient
WHERE gender = 'Male';

-- Q3: Head nurses who are registered
SELECT name, position, registered
FROM nurse
WHERE position = 'Head Nurse' AND registered = 'Yes';

-- Q4: Nurses who are Team Leaders OR not registered
SELECT name, position, registered
FROM nurse
WHERE position = 'Team Leader' OR registered = 'No';

-- Q5: Average procedure cost
SELECT AVG(cost) AS avg_cost
FROM procedures;

-- Q6: Procedures costing more than 2000
SELECT name AS procedure_name, cost AS procedure_cost
FROM procedures
WHERE cost > 2000;

-- Q9: Second most expensive procedure
-- (Q7 and Q8 are UPDATE / ALTER examples; they live in maintenance_examples.sql
--  because they change the data and would break the other queries.)
SELECT name, cost
FROM procedures
WHERE cost = (
    SELECT MAX(cost)
    FROM procedures
    WHERE cost < (SELECT MAX(cost) FROM procedures)
);

-- Q10: Patients whose first name starts with A
SELECT name || ' ' || surname AS full_name, gender
FROM patient
WHERE name LIKE 'A%';

-- Q11: Patients whose first name has M as its third letter
SELECT name || ' ' || surname AS full_name, gender
FROM patient
WHERE name LIKE '__M%';

-- Q12: Patients whose first name starts with J and ends with S
-- (The original asked for J...Z, which matches nobody in this data, so the
--  pattern was changed to S to give the query something to find.)
SELECT name || ' ' || surname AS full_name, gender
FROM patient
WHERE name LIKE 'J%S';

-- Q13: Patients with ids 11 to 20
SELECT *
FROM patient
WHERE patient_id BETWEEN 11 AND 20;

-- Q14: Physicians who head a department
SELECT p.name AS doctor_name, d.dept_name
FROM physician p
JOIN department d ON p.employeeid = d.head;

-- Q15: Patients and their primary-check physician
SELECT p.name || ' ' || p.surname AS patient_name,
       ph.name AS primary_physician
FROM patient p
LEFT JOIN physician ph ON p.primary_check = ph.employeeid;

-- Q16: Physicians and their primary department
SELECT p.name AS physician_name, d.dept_name AS department_name
FROM physician p
JOIN affiliated_with aw ON p.employeeid = aw.physicianid
JOIN department d ON aw.departmentid = d.department_id
WHERE aw.primaryaffiliation = 't';

-- Q17: Physician, position and every department they are affiliated with
SELECT p.name AS physician_name, p.position, d.dept_name AS department_name
FROM physician p
JOIN affiliated_with a ON p.employeeid = a.physicianid
JOIN department d ON a.departmentid = d.department_id;

-- Q18: Patients with their physician, diagnosis and prescription
SELECT ph.employeeid,
       ph.name AS physician_name,
       ph.position,
       p.patient_id,
       p.name || ' ' || p.surname AS patient_name,
       p.gender,
       pd.diagnosis,
       pd.prescription
FROM patient_diagnosis pd
JOIN physician ph ON pd.physician_id = ph.employeeid
JOIN patient p ON p.patient_id = pd.patient_id;

-- Q19: Most expensive procedure
SELECT name, cost
FROM procedures
WHERE cost = (SELECT MAX(cost) FROM procedures);

-- Q20: Patients diagnosed with Chronic Pain
SELECT *
FROM patient
WHERE patient_id IN (
    SELECT patient_id
    FROM patient_diagnosis
    WHERE diagnosis = 'Chronic Pain'
);

-- Q21: Procedures costing above average
SELECT name, cost
FROM procedures
WHERE cost > (SELECT AVG(cost) FROM procedures);

-- Q22: Procedures costing below average
SELECT name, cost
FROM procedures
WHERE cost < (SELECT AVG(cost) FROM procedures);

-- Q23: Physicians whose position contains Senior or Head Chief
SELECT *
FROM physician
WHERE position LIKE '%Senior%' OR position LIKE '%Head Chief%';

-- Q24: Physicians with NO primary affiliation (corrected)
-- The original filtered on primaryaffiliation = 'f'. That also returns doctors
-- who have a secondary affiliation AND a primary one (Dr. Rivera and Dr. Patel
-- are both in this data), so it listed 10 doctors when the right answer is 8.
-- The fix is to look for doctors who have no 't' row at all.
SELECT employeeid, name, position
FROM physician p
WHERE NOT EXISTS (
    SELECT 1
    FROM affiliated_with a
    WHERE a.physicianid = p.employeeid
      AND a.primaryaffiliation = 't'
);

-- Q25: Patients per physician, ranked (window function)
-- RANK gives tied physicians the same rank; the next rank is skipped.
SELECT ph.name AS physician_name,
       COUNT(p.patient_id) AS patients,
       RANK() OVER (ORDER BY COUNT(p.patient_id) DESC) AS workload_rank
FROM physician ph
JOIN patient p ON p.primary_check = ph.employeeid
GROUP BY ph.employeeid, ph.name
ORDER BY workload_rank, physician_name;

-- Q26: Physicians per department (any affiliation), most staffed first
SELECT d.dept_name,
       COUNT(a.physicianid) AS physicians,
       SUM(CASE WHEN a.primaryaffiliation = 't' THEN 1 ELSE 0 END) AS primary_physicians
FROM department d
LEFT JOIN affiliated_with a ON a.departmentid = d.department_id
GROUP BY d.department_id, d.dept_name
ORDER BY physicians DESC, d.dept_name;

-- Q27: Running total of procedure cost, cheapest first (window function)
SELECT name,
       cost,
       SUM(cost) OVER (ORDER BY cost, code) AS running_total
FROM procedures
ORDER BY cost, code;

-- Q28: Procedures grouped into cost bands (CASE)
SELECT CASE
           WHEN cost < 1000 THEN 'Low (under 1000)'
           WHEN cost < 5000 THEN 'Mid (1000-4999)'
           ELSE 'High (5000 and up)'
       END AS cost_band,
       COUNT(*) AS procedures,
       MIN(cost) AS cheapest,
       MAX(cost) AS dearest
FROM procedures
GROUP BY cost_band
ORDER BY cheapest;

-- Q29: Diagnoses that appear more than once, with how many times
SELECT diagnosis, COUNT(*) AS cases
FROM patient_diagnosis
GROUP BY diagnosis
HAVING COUNT(*) > 1
ORDER BY cases DESC, diagnosis;

-- Q30: Physicians who are nobody's primary-check physician
SELECT ph.employeeid, ph.name, ph.position
FROM physician ph
WHERE NOT EXISTS (
    SELECT 1 FROM patient p WHERE p.primary_check = ph.employeeid
)
ORDER BY ph.employeeid;

-- Q31: Patients per department, using each doctor's primary department (CTE)
WITH primary_dept AS (
    SELECT physicianid, departmentid
    FROM affiliated_with
    WHERE primaryaffiliation = 't'
),
patients_by_dept AS (
    SELECT pd.departmentid, COUNT(*) AS patients
    FROM patient p
    JOIN primary_dept pd ON pd.physicianid = p.primary_check
    GROUP BY pd.departmentid
)
SELECT d.dept_name,
       COALESCE(pb.patients, 0) AS patients
FROM department d
LEFT JOIN patients_by_dept pb ON pb.departmentid = d.department_id
ORDER BY patients DESC, d.dept_name;

-- Q32: Share of registered nurses by position
SELECT position,
       COUNT(*) AS nurses,
       SUM(CASE WHEN registered = 'Yes' THEN 1 ELSE 0 END) AS registered,
       ROUND(100.0 * SUM(CASE WHEN registered = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_registered
FROM nurse
GROUP BY position
ORDER BY pct_registered DESC, position;

-- Q33: Second most expensive procedure again, with DENSE_RANK
-- Same answer as Q9 without the nested MAX subqueries. It also copes with ties.
SELECT name, cost
FROM (
    SELECT name, cost, DENSE_RANK() OVER (ORDER BY cost DESC) AS r
    FROM procedures
) ranked
WHERE r = 2;
