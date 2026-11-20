-- 보안 점검(function_search_path_mutable): 코드 만들기 함수의 search_path 고정.
-- 남은 경고(security definer 함수를 로그인한 사용자·익명이 부름)는 설계대로다: 표에 직접 쓰기 정책을 두지 않고 쓰기는 이 함수들로만 한다.
-- reports 표에 정책이 없는 것도 설계대로다(누구도 직접 읽지 않음).
alter function public._new_code() set search_path = public;
