-- =========================================================
-- I. TRIGGER
-- =========================================================

/*MENU
Sau khi chốt thì sẽ lập bảng menu ra
*/
--Chống trùng lịch đặt phòng: Ví dụ 1 lịch là 9 - 12 và lịch khác là từ 11 - 13 -> bị overlap
CREATE OR REPLACE TRIGGER booking_room_no_overlap
BEFORE INSERT OR UPDATE ON booking_room
FOR EACH ROW
DECLARE
    v_conflict_booking_id           booking.booking_id%TYPE;
    v_conflict_booking_room_id      booking_room.room_id%TYPE;
BEGIN 
    --sẽ chọn mã booking và booking_room để đối chiếu giữa old và new
    SELECT br.booking_id, br.booking_room_id
    INTO v_conflict_booking_id, v_conflict_booking_room_id
    FROM booking_room br
    JOIN booking b_old
        ON br.booking_id = b_old.booking_id
    JOIN booking b_new
        ON br.booking_id = :NEW.booking_id
        
    WHERE br.room_id = :NEW.room_id -- xét mã phòng mới insert
    AND br.booking_room_id <> :NEW.booking_room_id -- tránh việc nó tự xét chính nó, mà hãy xét các mã phòng còn lại
    AND b_old.status <> 'CANCELLED' -- trạng thái phải khác hủy thì mới xét
    AND b_new.status <> 'CANCELLED' -- trạng thái phải khác hủy
    AND b_new.checkin_expected_at < b_old.checkout_expected_at
    AND b_new.checkout_expected_at > b_old.checkin_expected_at 
    -- điều kiện tránh overlap
    AND ROWNUM = 1;

    RAISE_APPLICATION_ERROR(
        -20001,
        'overlap booking_id = ' || v_conflict_booking_id ||
        'overlap booking_room_id = ' || v_conflict_booking_room_id
    );
    --hiện mã booking và mã booking phòng bị trùng lặp

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/
-- 1 nhân viên không thể thực hiện 2 dịch vụ cùng 1 lúc
CREATE OR REPLACE TRIGGER employee_no_overlap
BEFORE INSERT OR UPDATE ON booking_services
FOR EACH ROW
DECLARE
    v_conflict_booking_service_id   booking_services.booking_service_id%TYPE;
    v_conflict_booking_id           booking_services.booking_id%TYPE;
    v_new_end_time                  TIMESTAMP(6) WITH TIME ZONE; --thời gian kết thúc dịch vụ mới
BEGIN

    IF :NEW.employee_id IS NULL 
       OR :NEW.service_id IS NULL
       OR :NEW.scheduled_at IS NULL
       OR :NEW.status NOT IN ('SCHEDULED', 'IN_PROGRESS') THEN 
        RETURN;
    END IF;-- dùng để kiểm tra các thuộc tính quan trọng không được bỏ trống cũng như trạng thái dịch vụ đã được sắp xếp và thực hiện

    SELECT fn_add_minutes(:NEW.scheduled_at, s.duration_minutes)-- hàm để tính ra thời gian kết thúc dịch vụ mới
    INTO v_new_end_time
    FROM services s
    WHERE s.service_id = :NEW.service_id;

    SELECT bs.booking_service_id, bs.booking_id
    INTO v_conflict_booking_service_id, v_conflict_booking_id
    FROM booking_services bs
    JOIN services s_old ON bs.service_id = s_old.service_id
        
    WHERE bs.employee_id = :NEW.employee_id-- xét nhân viên được chọn để thực hiện dịch vụ mới
      AND bs.booking_service_id <> :NEW.booking_service_id-- mã booking dịch vụ phải khác với mã mới để tránh việc xét chính nó
      AND bs.status IN ('SCHEDULED', 'IN_PROGRESS')-- chỉ xét các dịch vụ đã lên lịch hoặc đang thực hiện
      AND bs.scheduled_at IS NOT NULL

      AND :NEW.scheduled_at < fn_add_minutes(bs.scheduled_at, s_old.duration_minutes)
      AND v_new_end_time > bs.scheduled_at
      --điều kiện để tránh các dịch vụ bị overlap
      AND ROWNUM = 1;

    RAISE_APPLICATION_ERROR(
        -20011,
        'Employee cannot perform two services at the same time. Conflicted booking_service_id = '
        || v_conflict_booking_service_id ||
        ',conflicted booking_id = ' || v_conflict_booking_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/
-- Trong cùng một booking, các dịch vụ không được trùng thời gian
CREATE OR REPLACE TRIGGER booking_service_no_overlap_same_booking
BEFORE INSERT OR UPDATE ON booking_services
FOR EACH ROW
DECLARE
    v_conflict_booking_service_id   booking_services.booking_service_id%TYPE;
    v_new_end_time                  TIMESTAMP(6) WITH TIME ZONE;
BEGIN
    IF :NEW.booking_id IS NULL
       OR :NEW.service_id IS NULL
       OR :NEW.scheduled_at IS NULL
       OR :NEW.status NOT IN ('SCHEDULED', 'IN_PROGRESS') THEN
        RETURN;
    END IF;

    SELECT fn_add_minutes(:NEW.scheduled_at, s.duration_minutes)
    INTO v_new_end_time
    FROM services s
    WHERE s.service_id = :NEW.service_id;

    SELECT bs.booking_service_id
    INTO v_conflict_booking_service_id
    FROM booking_services bs
    JOIN services s_old ON bs.service_id = s_old.service_id 
      
    WHERE bs.booking_id = :NEW.booking_id
      AND bs.booking_service_id <> :NEW.booking_service_id
      AND bs.status IN ('SCHEDULED', 'IN_PROGRESS')
      AND bs.scheduled_at IS NOT NULL
      AND :NEW.scheduled_at < fn_add_minutes(bs.scheduled_at, s_old.duration_minutes)
      AND v_new_end_time > bs.scheduled_at
      AND ROWNUM = 1;

    RAISE_APPLICATION_ERROR(
        -20012,
        'Service time overlap in the same booking. Conflicted booking_service_id = '
        || v_conflict_booking_service_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/

-- Một thú cưng không được ở hai nơi lưu trú cùng lúc
CREATE OR REPLACE TRIGGER pet_no_overlap
BEFORE INSERT OR UPDATE ON booking_room_pet
FOR EACH ROW
DECLARE
    v_conflict_booking_id        booking.booking_id%TYPE;
    v_conflict_booking_room_id   booking_room.booking_room_id%TYPE;
BEGIN
    SELECT b_old.booking_id, br_old.booking_room_id
    INTO v_conflict_booking_id, v_conflict_booking_room_id
    FROM booking_room_pet brp_old
    JOIN booking_room br_old ON brp_old.booking_room_id = br_old.booking_room_id
    JOIN booking b_old ON br_old.booking_id = b_old.booking_id
    JOIN booking_room br_new ON br_new.booking_room_id = :NEW.booking_room_id
    JOIN booking b_new ON br_new.booking_id = b_new.booking_id
    
    WHERE brp_old.pet_id = :NEW.pet_id
      AND brp_old.booking_room_id <> :NEW.booking_room_id
      AND b_old.status <> 'CANCELLED'
      AND b_new.status <> 'CANCELLED'
      AND b_new.checkin_expected_at < b_old.checkout_expected_at
      AND b_new.checkout_expected_at > b_old.checkin_expected_at
      AND ROWNUM = 1;

    RAISE_APPLICATION_ERROR(
        -20021,
        'Pet overlap detected. pet_id = ' || :NEW.pet_id ||
        ' is already assigned in booking_id = ' || v_conflict_booking_id ||
        ',conflicted booking_room_id = ' || v_conflict_booking_room_id
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END;
/
-- Thêm thú cưng vào phòng đã có thú cưng trước đó
CREATE OR REPLACE TRIGGER add_pet_same_room
BEFORE INSERT ON booking_room_pet
FOR EACH ROW
DECLARE
    v_max_pets            type_room.max_pets%TYPE;
    v_max_weight_kg       type_room.max_weight_kg%TYPE;
    v_exist_pet_count     NUMBER;
    v_new_pet_weight      pet.weight_kg%TYPE;
    v_new_customer_id     pet.customer_id%TYPE;
    v_old_customer_id     pet.customer_id%TYPE;
BEGIN
    SELECT tr.max_pets, tr.max_weight_kg
    INTO v_max_pets, v_max_weight_kg
    FROM type_room tr
    JOIN room r ON r.type_room_id = tr.type_room_id
    JOIN booking_room br ON br.room_id = r.room_id
    WHERE br.booking_room_id = :NEW.booking_room_id;
    
    SELECT COUNT(*)
    INTO v_exist_pet_count
    FROM booking_room_pet
    WHERE booking_room_id = :NEW.booking_room_id;

    IF v_exist_pet_count = 0 THEN
        RETURN;
    END IF;
    
    IF v_max_pets < 2 THEN
        RAISE_APPLICATION_ERROR(-20041, 'This room type does not allow shared stay.');
    END IF;

    IF v_existing_pet_count + 1 > v_max_pets THEN
        RAISE_APPLICATION_ERROR(-20042, 'Room capacity exceeded.');
    END IF;

    SELECT customer_id, weight_kg
    INTO v_new_customer_id, v_new_pet_weight
    FROM pet
    WHERE pet_id = :NEW.pet_id;

    SELECT p.customer_id
    INTO v_old_customer_id
    FROM booking_room_pet brp
    JOIN pet p ON brp.pet_id = p.pet_id
    WHERE brp.booking_room_id = :NEW.booking_room_id
    AND ROWNUM = 1;

   IF v_new_customer_id <> v_old_customer_id THEN
        RAISE_APPLICATION_ERROR(-20043, 'Only pets of the same owner can share the room.');
    END IF;

   IF v_max_weight_kg IS NOT NULL
       AND v_new_pet_weight IS NOT NULL
       AND v_new_pet_weight > v_max_weight_kg THEN
        RAISE_APPLICATION_ERROR(-20044, 'Pet weight exceeds room limit.');
    END IF;
END;

--Khách hàng không thể thanh toán một hóa đơn chưa tồn tại
CREATE OR REPLACE TRIGGER trg_payment_time_valid
BEFORE INSERT OR UPDATE ON payments
FOR EACH ROW
DECLARE
    v_order_created_at   orders.created_at%TYPE;
BEGIN
    --Nếu thanh toán thành công thì paid_at bắt buộc phải có
    IF :NEW.status = 'SUCCESS' AND :NEW.paid_at IS NULL THEN
        RAISE_APPLICATION_ERROR(
            -20062,
            'Invalid payment data. paid_at must not be NULL when status = SUCCESS.'
        );
    END IF;
    --Nếu đang chờ xử lý thì paid_at phải để trống
    IF :NEW.status = 'PENDING' AND :NEW.paid_at IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(
            -20063,
            'Invalid payment data. paid_at must be NULL when status = PENDING.'
        );
    END IF;
    --Nếu chưa có paid_at thì không cần kiểm tra tiếp thời gian
    IF :NEW.paid_at IS NULL THEN
        RETURN;
    END IF;
    --Lấy thời điểm khởi tạo của hóa đơn tương ứng
    SELECT o.created_at
    INTO v_order_created_at
    FROM orders o
    WHERE o.order_id = :NEW.order_id;
    --paid_at phải cùng lúc hoặc sau created_at của order
    IF :NEW.paid_at < v_order_created_at THEN
        RAISE_APPLICATION_ERROR(
            -20061,
            'Invalid payment time. paid_at must be greater than or equal to order created_at.'
        );
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20064,
            'Invalid payment data. The referenced order_id does not exist.'
        );
END;
/
