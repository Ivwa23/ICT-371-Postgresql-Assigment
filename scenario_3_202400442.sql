DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;

CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(10) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED', 'COMPLETED')),
    allocated_at   TIMESTAMP DEFAULT now()
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % : FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % : ONE SPACE LEFT', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % : SEVERAL SPACES (%)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
END $$;
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check %', n;
    END LOOP;
END $$;
CREATE OR REPLACE PROCEDURE allocate_room(p_student_number VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student_number IS NULL OR trim(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE NOTICE 'Allocation rejected for student %: room % is full',
            p_student_number, p_room_id;
    ELSE
        UPDATE hostel_rooms SET available_spaces = available_spaces - 1
        WHERE room_id = p_room_id;

        INSERT INTO allocations (student_number, room_id)
        VALUES (trim(p_student_number), p_room_id);

        RAISE NOTICE 'Student % allocated to room %', p_student_number, p_room_id;
    END IF;
END $$;
CALL allocate_room('S2001', 1);
CALL allocate_room('S2002', 2);
CALL allocate_room('S2003', 3);
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETED' THEN
        RAISE NOTICE 'Allocation % already checked out; no space freed', p_allocation_id;
    ELSE
        UPDATE allocations SET status = 'COMPLETED' WHERE allocation_id = p_allocation_id;
        UPDATE hostel_rooms SET available_spaces = available_spaces + 1
        WHERE room_id = v_room_id;
        RAISE NOTICE 'Allocation % checked out; one bed space freed', p_allocation_id;
    END IF;
END $$;
CALL check_out(2);
CALL check_out(2);

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces FROM hostel_rooms
        WHERE available_spaces <= 1 ORDER BY available_spaces, room_number;
    v_room   hostel_rooms.room_number%TYPE;
    v_spaces hostel_rooms.available_spaces%TYPE;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_room, v_spaces;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full or nearly full: room % (% spaces left)', v_room, v_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;