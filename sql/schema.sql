-- Hospital database schema.
--
-- Written in plain SQL that runs unchanged on SQLite (which is what the tests
-- use) and, apart from the notes at the bottom of README.md, on MySQL and
-- PostgreSQL. Tables are created parents first: `department` and `physician`
-- must exist before anything that has a foreign key pointing at them.
--
-- The first version of this project created `affiliated_with` before
-- `department`, so the script failed on MySQL ("can't create table ... foreign
-- key constraint is incorrectly formed"). This order fixes that.

CREATE TABLE physician (
    employeeid INTEGER PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    position   VARCHAR(150) NOT NULL
);

CREATE TABLE department (
    department_id INTEGER PRIMARY KEY,
    dept_name     VARCHAR(150) NOT NULL,
    head          INTEGER NOT NULL,
    FOREIGN KEY (head) REFERENCES physician (employeeid)
);

CREATE TABLE affiliated_with (
    physicianid        INTEGER NOT NULL,
    departmentid       INTEGER NOT NULL,
    -- 't' = this is the physician's primary department, 'f' = secondary
    primaryaffiliation VARCHAR(1) NOT NULL CHECK (primaryaffiliation IN ('t', 'f')),
    PRIMARY KEY (physicianid, departmentid),
    FOREIGN KEY (physicianid)  REFERENCES physician (employeeid),
    FOREIGN KEY (departmentid) REFERENCES department (department_id)
);

-- The original had no primary key here, so nothing stopped two nurses sharing an id.
CREATE TABLE nurse (
    nurse_id   INTEGER PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    position   VARCHAR(150) NOT NULL,
    registered VARCHAR(10) NOT NULL CHECK (registered IN ('Yes', 'No'))
);

CREATE TABLE patient (
    patient_id    INTEGER PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    surname       VARCHAR(100) NOT NULL,
    address       VARCHAR(100) NOT NULL,
    gender        VARCHAR(150) NOT NULL,
    phone         VARCHAR(150) NOT NULL,
    primary_check INTEGER NOT NULL,
    FOREIGN KEY (primary_check) REFERENCES physician (employeeid)
);

CREATE TABLE patient_diagnosis (
    diagnosis    VARCHAR(150) NOT NULL,
    prescription VARCHAR(150) NOT NULL,
    patient_id   INTEGER NOT NULL,
    physician_id INTEGER NOT NULL,
    FOREIGN KEY (patient_id)   REFERENCES patient (patient_id),
    FOREIGN KEY (physician_id) REFERENCES physician (employeeid)
);

CREATE TABLE procedures (
    code INTEGER PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    cost INTEGER NOT NULL CHECK (cost > 0)
);
