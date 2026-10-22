package com.planblindbox;

import org.apache.ibatis.session.SqlSessionFactory;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.autoconfigure.MybatisProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class MyBatisConfigTest {

    @Autowired
    private Environment environment;

    @Autowired
    private MybatisProperties mybatisProperties;

    @Autowired
    private SqlSessionFactory sqlSessionFactory;

    @Test
    void testConfig() {

        System.out.println(
                "Environment = "
                        + environment.getProperty(
                        "mybatis.configuration.map-underscore-to-camel-case"
                )
        );

        MybatisProperties.CoreConfiguration configuration =
                mybatisProperties.getConfiguration();

        System.out.println(
                "MybatisProperties = "
                        + (configuration == null
                        ? null
                        : configuration.getMapUnderscoreToCamelCase())
        );

        System.out.println(
                "SqlSessionFactory = "
                        + sqlSessionFactory
                        .getConfiguration()
                        .isMapUnderscoreToCamelCase()
        );
        System.out.println(
                "spring.application.name = "
                        + environment.getProperty("spring.application.name")
        );

        System.out.println(
                "spring.datasource.url = "
                        + environment.getProperty("spring.datasource.url")
        );

        System.out.println(
                "mybatis.camel = "
                        + environment.getProperty(
                        "mybatis.configuration.map-underscore-to-camel-case"
                )
        );
    }
}