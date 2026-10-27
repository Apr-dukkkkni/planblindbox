package com.planblindbox.exception;

import com.planblindbox.common.Result;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.BindException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.stream.Collectors;

/** 统一 HTTP 错误体：{ "code": HTTP状态码, "message": 描述, "data": null }。 */
@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<Result<Void>> business(BusinessException e) {
        return response(e.getStatus(), e.getMessage());
    }

    // 渐进迁移：既有 Task/Habit 服务暂时仍抛 ResponseStatusException。
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Result<Void>> legacy(ResponseStatusException e) {
        HttpStatusCode status = e.getStatusCode();
        if (!status.is4xxClientError()) {
            log.error("Non-client ResponseStatusException", e);
            return internalError();
        }
        String reason = e.getReason();
        return response(status, (reason == null || reason.isBlank()) ? "请求无法处理" : reason);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Result<Void>> requestBodyValidation(MethodArgumentNotValidException e) {
        String fields = e.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + " " + error.getDefaultMessage())
                .distinct().sorted().collect(Collectors.joining("；"));
        return response(HttpStatus.BAD_REQUEST,
                fields.isBlank() ? "请求参数校验失败" : "请求参数校验失败：" + fields);
    }

    @ExceptionHandler(BindException.class)
    public ResponseEntity<Result<Void>> binding(BindException e) {
        return response(HttpStatus.BAD_REQUEST, "请求参数校验失败");
    }

    @ExceptionHandler({ConstraintViolationException.class, HandlerMethodValidationException.class})
    public ResponseEntity<Result<Void>> methodValidation(Exception e) {
        return response(HttpStatus.BAD_REQUEST, "请求参数校验失败");
    }

    @ExceptionHandler({HttpMessageNotReadableException.class,
            MissingServletRequestParameterException.class,
            MethodArgumentTypeMismatchException.class})
    public ResponseEntity<Result<Void>> malformedRequest(Exception e) {
        return response(HttpStatus.BAD_REQUEST, "请求参数格式错误或缺少必填参数");
    }

    @ExceptionHandler({NoResourceFoundException.class, NoHandlerFoundException.class})
    public ResponseEntity<Result<Void>> notFound(Exception e) {
        return response(HttpStatus.NOT_FOUND, "接口不存在");
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<Result<Void>> methodNotAllowed(HttpRequestMethodNotSupportedException e) {
        return response(HttpStatus.METHOD_NOT_ALLOWED, "请求方法不支持");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Result<Void>> unexpected(Exception e) {
        log.error("Unhandled exception during request", e);
        return internalError();
    }

    private ResponseEntity<Result<Void>> internalError() {
        return response(HttpStatus.INTERNAL_SERVER_ERROR, "服务器内部错误");
    }

    private ResponseEntity<Result<Void>> response(HttpStatusCode status, String message) {
        return ResponseEntity.status(status).body(Result.error(status.value(), message));
    }
}
