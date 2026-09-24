"""Tests for the hospital SQL project.

Most checks work out the expected answer in plain Python from the raw tables,
then compare it with what the SQL returned. That way a wrong query can't pass
just because it agrees with itself.
"""

import os
import re
import sqlite3
import sys
from collections import Counter

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from run_queries import build_database, load_queries, run  # noqa: E402

QUERIES = load_queries()


@pytest.fixture()
def con():
    return build_database()


def rows(con, number):
    return run(con, QUERIES[number][1])[1]


def table(con, name):
    return con.execute(f"SELECT * FROM {name}").fetchall()


# ------------------------------------------------------------------ loading
def test_row_counts(con):
    expected = {"physician": 35, "department": 15, "affiliated_with": 37, "nurse": 33,
                "patient": 39, "patient_diagnosis": 39, "procedures": 20}
    for name, n in expected.items():
        assert con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0] == n, name


def test_no_foreign_key_violations(con):
    assert con.execute("PRAGMA foreign_key_check").fetchall() == []


def test_all_queries_are_found_and_run(con):
    assert sorted(QUERIES) == [n for n in range(1, 34) if n not in (7, 8)]
    for number, (_, sql) in QUERIES.items():
        assert sql, f"Q{number} has no SQL"
        run(con, sql)  # raises if the SQL is invalid


# ------------------------------------------------------------ the constraints
def test_schema_rejects_bad_rows(con):
    with pytest.raises(sqlite3.IntegrityError):  # department 99 doesn't exist
        con.execute("INSERT INTO affiliated_with VALUES (1, 99, 't')")
    with pytest.raises(sqlite3.IntegrityError):  # nurse ids must be unique now
        con.execute("INSERT INTO nurse VALUES (1, 'Copy Cat', 'Nurse', 'Yes')")
    with pytest.raises(sqlite3.IntegrityError):  # a procedure can't be free
        con.execute("INSERT INTO procedures VALUES (99, 'Free scan', 0)")
    with pytest.raises(sqlite3.IntegrityError):  # primaryaffiliation is 't' or 'f'
        con.execute("INSERT INTO affiliated_with VALUES (1, 2, 'x')")


# ------------------------------------------------- the bug in the original Q24
def test_original_q24_was_wrong_and_the_fix_is_right(con):
    original = {r[0] for r in con.execute(
        "SELECT employeeid FROM physician WHERE employeeid IN "
        "(SELECT physicianid FROM affiliated_with WHERE primaryaffiliation = 'f')")}
    fixed = {r[0] for r in rows(con, 24)}

    # independent calculation: doctors with no 't' row at all
    has_primary = {p for p, _, flag in table(con, "affiliated_with") if flag == "t"}
    everyone = {r[0] for r in table(con, "physician")}
    assert fixed == everyone - has_primary

    assert len(original) == 10 and len(fixed) == 8
    assert original - fixed == {3, 7}  # Dr. Rivera and Dr. Patel do have a primary department


# ------------------------------------------------------- original queries
def test_pattern_queries_match_python(con):
    patients = [(r[1], r[2]) for r in table(con, "patient")]
    starts_a = sorted(f"{n} {s}" for n, s in patients if n.lower().startswith("a"))
    assert sorted(r[0] for r in rows(con, 10)) == starts_a
    third_m = sorted(f"{n} {s}" for n, s in patients if len(n) > 2 and n[2].lower() == "m")
    assert sorted(r[0] for r in rows(con, 11)) == third_m
    j_s = sorted(f"{n} {s}" for n, s in patients if n.lower().startswith("j") and n.lower().endswith("s"))
    assert sorted(r[0] for r in rows(con, 12)) == j_s and j_s


def test_procedure_cost_queries(con):
    costs = sorted(r[2] for r in table(con, "procedures"))
    avg = sum(costs) / len(costs)
    assert rows(con, 5)[0][0] == pytest.approx(avg)
    assert len(rows(con, 6)) == sum(c > 2000 for c in costs)
    assert len(rows(con, 21)) == sum(c > avg for c in costs)
    assert len(rows(con, 22)) == sum(c < avg for c in costs)
    assert rows(con, 19)[0][1] == max(costs)
    second = sorted(set(costs))[-2]
    assert rows(con, 9)[0][1] == second
    assert rows(con, 33)[0][1] == second  # the DENSE_RANK version agrees with the nested-MAX version


def test_joins_keep_every_row(con):
    assert len(rows(con, 15)) == 39          # LEFT JOIN: every patient once
    assert len(rows(con, 18)) == 39          # every patient has exactly one diagnosis
    assert len(rows(con, 17)) == 37          # one row per affiliation
    assert len(rows(con, 14)) == 15          # one head per department


# ---------------------------------------------------------- new queries
def test_q25_workload(con):
    per_doc = Counter(r[6] for r in table(con, "patient"))
    result = rows(con, 25)
    assert sum(r[1] for r in result) == 39
    assert {r[1] for r in result if r[2] == 1} == {max(per_doc.values())}
    ranks = [r[2] for r in result]
    assert ranks == sorted(ranks)


def test_q26_department_staffing(con):
    aff = table(con, "affiliated_with")
    total = Counter(d for _, d, _ in aff)
    primary = Counter(d for _, d, f in aff if f == "t")
    names = dict(con.execute("SELECT department_id, dept_name FROM department").fetchall())
    for dept_name, physicians, primary_physicians in rows(con, 26):
        dept_id = next(k for k, v in names.items() if v == dept_name)
        assert physicians == total[dept_id]
        assert primary_physicians == primary[dept_id]


def test_q27_running_total(con):
    result = rows(con, 27)
    assert result[-1][2] == sum(r[2] for r in table(con, "procedures"))
    running = 0
    for _, cost, total in result:
        running += cost
        assert total == running


def test_q28_bands_cover_every_procedure(con):
    result = rows(con, 28)
    assert sum(r[1] for r in result) == 20
    costs = [r[2] for r in table(con, "procedures")]
    bands = {r[0]: r[1] for r in result}
    assert bands["Low (under 1000)"] == sum(c < 1000 for c in costs)
    assert bands["High (5000 and up)"] == sum(c >= 5000 for c in costs)


def test_q29_repeated_diagnoses(con):
    counts = Counter(r[0] for r in table(con, "patient_diagnosis"))
    expected = {d: n for d, n in counts.items() if n > 1}
    assert dict(rows(con, 29)) == expected


def test_q30_and_q31_agree_with_python(con):
    has_patient = {r[6] for r in table(con, "patient")}
    idle = {r[0] for r in table(con, "physician")} - has_patient
    assert {r[0] for r in rows(con, 30)} == idle

    primary_dept = {p: d for p, d, f in table(con, "affiliated_with") if f == "t"}
    by_dept = Counter(primary_dept[r[6]] for r in table(con, "patient") if r[6] in primary_dept)
    names = dict(con.execute("SELECT department_id, dept_name FROM department").fetchall())
    expected = {names[d]: by_dept.get(d, 0) for d in names}
    assert dict(rows(con, 31)) == expected


def test_q32_registered_share(con):
    nurses = table(con, "nurse")
    for position, n, registered, pct in rows(con, 32):
        group = [r for r in nurses if r[2] == position]
        assert n == len(group)
        assert registered == sum(r[3] == "Yes" for r in group)
        assert pct == pytest.approx(round(100 * registered / n, 1))


# ---------------------------------------------------- the data itself is sound
def test_data_quality(con):
    q = lambda sql: con.execute(sql).fetchall()
    assert q("SELECT physicianid FROM affiliated_with WHERE primaryaffiliation='t' "
             "GROUP BY physicianid HAVING COUNT(*) > 1") == []          # one primary each
    assert q("SELECT 1 FROM department d WHERE NOT EXISTS (SELECT 1 FROM affiliated_with a "
             "WHERE a.physicianid = d.head AND a.departmentid = d.department_id)") == []  # heads work in their dept
    assert q("SELECT 1 FROM patient p WHERE NOT EXISTS (SELECT 1 FROM patient_diagnosis d "
             "WHERE d.patient_id = p.patient_id)") == []                 # every patient has a diagnosis
    assert q("SELECT name, surname FROM patient GROUP BY name, surname HAVING COUNT(*) > 1") == []


# ------------------------------------------------------ Q7 and Q8 (they change data)
def test_maintenance_examples_run_on_a_copy(con):
    path = os.path.join(ROOT, "sql", "maintenance_examples.sql")
    with open(path, encoding="utf-8") as f:
        con.executescript(f.read())
    assert con.execute("SELECT name, surname FROM patient WHERE patient_id = 5").fetchone() == ("Robert", "Fernandez")
    columns = [r[1] for r in con.execute("PRAGMA table_info(patient)")]
    assert "phone" not in columns
    assert re.fullmatch(r"\d+", str(con.execute("SELECT COUNT(*) FROM patient").fetchone()[0]))
