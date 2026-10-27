package com.planblindbox.exception;

import org.springframework.http.HttpStatus;

import java.util.Objects;

/**
 * 可向客户端明确说明的业务错误（400/404/409 等）。
 * 系统故障不应使用本类向客户端暴露内部报错细节。
 */
public class BusinessException extends RuntimeException {

    private final HttpStatus status;

    public BusinessException(HttpStatus status, String message) {
        super(message);
        this.status = Objects.requireNonNull(status, "status");
        if (!status.is4xxClientError()) {
            throw new IllegalArgumentException("BusinessException 仅用于 4xx 业务错误");
        }
        if (message == null || message.isBlank()) {
            throw new IllegalArgumentException("业务错误提示不能为空");
        }
    }

    public HttpStatus getStatus() {
        return status;
    }
}
