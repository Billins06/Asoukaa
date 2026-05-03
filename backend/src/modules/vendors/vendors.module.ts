import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { VendorsController } from './vendors.controller';
import { VendorsService }    from './vendors.service';
import { VendorProfile }     from '../users/entities/vendor-profile.entity';
import { UserRole }          from '../users/entities/user-role.entity';
import { User }              from '../users/entities/user.entity';
import { CommonModule }      from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([VendorProfile, UserRole, User]),
    CommonModule,
  ],
  controllers: [VendorsController],
  providers:   [VendorsService],
  exports:     [VendorsService, TypeOrmModule],
})
export class VendorsModule {}