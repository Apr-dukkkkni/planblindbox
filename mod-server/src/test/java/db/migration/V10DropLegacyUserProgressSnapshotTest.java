package db.migration;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

import org.flywaydb.core.api.FlywayException;
import org.flywaydb.core.api.migration.Context;
import org.junit.jupiter.api.Test;

class V10DropLegacyUserProgressSnapshotTest {

    @Test
    void dropsTableWhenItIsEmpty() throws Exception {
        try (Connection connection = DriverManager.getConnection(
                "jdbc:h2:mem:v10_empty;MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "")) {
            createSnapshotTable(connection);

            Context context = mock(Context.class);
            when(context.getConnection()).thenReturn(connection);

            new V10__DropLegacyUserProgressSnapshot().migrate(context);

            assertFalse(tableExists(connection));
        }
    }

    @Test
    void refusesToDropTableWhenRowsRemain() throws Exception {
        try (Connection connection = DriverManager.getConnection(
                "jdbc:h2:mem:v10_nonempty;MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "")) {
            createSnapshotTable(connection);
            try (Statement statement = connection.createStatement()) {
                statement.executeUpdate(
                    "INSERT INTO user_progress_snapshot "
                        + "(user_id, revision, schema_version, payload) "
                        + "VALUES (1, 1, 1, '{}')"
                );
            }

            Context context = mock(Context.class);
            when(context.getConnection()).thenReturn(connection);

            assertThrows(
                FlywayException.class,
                () -> new V10__DropLegacyUserProgressSnapshot().migrate(context)
            );
            assertTrue(tableExists(connection));
        }
    }

    private static void createSnapshotTable(Connection connection) throws Exception {
        try (Statement statement = connection.createStatement()) {
            statement.execute(
                "CREATE TABLE user_progress_snapshot ("
                    + "user_id BIGINT PRIMARY KEY, "
                    + "revision BIGINT NOT NULL, "
                    + "schema_version INT NOT NULL, "
                    + "payload JSON NOT NULL, "
                    + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
                    + ")"
            );
        }
    }

    private static boolean tableExists(Connection connection) throws Exception {
        try (ResultSet result = connection.getMetaData().getTables(
                null, null, "USER_PROGRESS_SNAPSHOT", new String[] {"TABLE"})) {
            return result.next();
        }
    }
}
