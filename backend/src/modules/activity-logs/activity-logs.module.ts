import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { ActivityLogsController } from './activity-logs.controller';
import { ActivityLogsService }    from './activity-logs.service';
import { ActivityLog }            from '../../common/entities/activity-log.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([ActivityLog]),
  ],
  controllers: [ActivityLogsController],
  providers:   [ActivityLogsService],
  exports:     [ActivityLogsService],
})
export class ActivityLogsModule {}