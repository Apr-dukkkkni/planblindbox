package db.migration;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import org.flywaydb.core.api.FlywayException;
import org.flywaydb.core.api.migration.BaseJavaMigration;
import org.flywaydb.core.api.migration.Context;

/**
 * Removes the retired V1 whole-database snapshot table.
 *
 * This migration intentionally refuses to drop the table if any rows remain.
 * The application must be stopped during migration so no legacy process can
 * write to the table between the emptiness check and DROP TABLE.
 */
public class V10__DropLegacyUserProgressSnapshot extends BaseJavaMigration {

    @Override
    public void migrate(Context context) throws Exception {
        Connection connection = context.getConnection();

        long rowCount;
        try (Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(
                 "SELECT COUNT(*) FROM user_progress_snapshot"
             )) {
            if (!result.next()) {
                throw new FlywayException(
                    "Could not verify user_progress_snapshot row count; refusing to drop table."
                );
            }
            rowCount = result.getLong(1);
        }

        if (rowCount != 0) {
            throw new FlywayException(
                "Refusing to drop user_progress_snapshot: "
                    + rowCount
                    + " row(s) remain. Export/review them before retrying V10."
            );
        }

        try (Statement statement = connection.createStatement()) {
            statement.execute("DROP TABLE user_progress_snapshot");
        }
    }
}
