import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UsersController } from './users.controller';
import { UsersService }    from './users.service';
import { User }            from './entities/user.entity';
import { UserRole }        from './entities/user-role.entity';
import { Address }         from './entities/address.entity';
import { VendorProfile }   from './entities/vendor-profile.entity';
import { DeliveryAgentProfile } from './entities/delivery-agent-profile.entity';
import { CommonModule }    from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      User,
      UserRole,
      Address,
      VendorProfile,
      DeliveryAgentProfile,
    ]),
    CommonModule,
  ],
  controllers: [UsersController],
  providers:   [UsersService],
  exports:     [UsersService, TypeOrmModule],
})
export class UsersModule {}