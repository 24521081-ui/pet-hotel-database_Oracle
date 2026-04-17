-- =========================================================
-- II. FUNCTION
-- =========================================================
CREATE OR REPLACE FUNCTION fn_add_minutes (
    p_start_time TIMESTAMP WITH TIME ZONE,
    p_minutes    NUMBER
)
RETURN TIMESTAMP WITH TIME ZONE
AS
BEGIN
    RETURN p_start_time + NUMTODSINTERVAL(p_minutes, 'MINUTE');
END;
/
-- dùng để tính thời gian thực hiện một dịch vụ của nhân viên từ lúc lập lịch
