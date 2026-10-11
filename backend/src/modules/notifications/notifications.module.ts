import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { NotificationsController } from './notifications.controller';
import { NotificationPreferencesController } from './notification-preferences.controller';
import { NotificationsService }    from './notifications.service';
import { Notification }            from './entities/notification.entity';
import { User }                    from '../users/entities/user.entity';
import { UserRole }                from '../users/entities/user-role.entity';
import { AdminAccount }            from '../auth/entities/admin-account.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Notification,
      User,
      UserRole,
      AdminAccount,
    ]),
  ],
  controllers: [NotificationsController, NotificationPreferencesController],
  providers:   [NotificationsService],
  exports:     [NotificationsService, TypeOrmModule],
})
export class NotificationsModule {}