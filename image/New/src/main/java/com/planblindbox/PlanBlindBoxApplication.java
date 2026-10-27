package com.planblindbox;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.io.Reader;


@MapperScan("com.planblindbox.mapper")
@SpringBootApplication
public class PlanBlindBoxApplication {

    public static void main(String[] args) {


        SpringApplication.run(PlanBlindBoxApplication.class, args);
    }

}
